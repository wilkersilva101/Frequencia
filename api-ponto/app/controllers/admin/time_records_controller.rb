module Admin
  class TimeRecordsController < Admin::ApplicationController
    include DuracaoFormatavel

    PER_PAGE = 50

    def index
      # Task 23.7 — CanCanCan: autorização explícita para leitura de registros.
      # Admin/gestor/operador podem visualizar (todos têm :read em :all).
      # Gestor também pode gerenciar TimeRecord, mas index é apenas leitura.
      authorize! :read, :all
      # Anos disponíveis pro dropdown de filtro — do ano do registro mais
      # antigo até o ano atual (nunca futuro). Sem registros ainda, mostra
      # só o ano atual.
      primeiro_ano = TimeRecord.minimum(:punched_at)&.year || Time.current.year
      @anos_disponiveis = (primeiro_ano..Time.current.year).to_a.reverse

      # Monta a query base
      registros = TimeRecord.includes(:user).order(punched_at: :asc)

      # Usuários não-admin (basic) veem apenas os próprios registros,
      # ignorando qualquer filtro de usuário vindo dos params.
      if current_user.admin?
        if params[:usuario].present?
          # Mesmo filtro/fonte do "Nome" em admin/frequentadores (pedido do
          # usuário, 2026-09-02): busca por nome via vínculo ativo do
          # pessoas2 (Pessoas::Vinculo.cpfs_por_nome), não pelo
          # `nome_completo` local nem pela tabela `pessoas` crua (que
          # incluiria gente com vínculo encerrado). Só retorna quem já tem
          # User local (TimeRecord só existe pra quem já bateu ponto, e
          # bater ponto exige User local).
          cpfs_encontrados = Pessoas::Vinculo.cpfs_por_nome(params[:usuario])
          usuarios_encontrados = User.where(cpf: cpfs_encontrados)
          registros = registros.where(user_id: usuarios_encontrados.select(:id))

          # Só entra no modo "um usuário só" (com o card de resumo mensal)
          # quando a busca resolve pra exatamente um usuário — com vários
          # resultados, continua na visão agregada (Usuário/Data/Marcações).
          @user = usuarios_encontrados.first if usuarios_encontrados.count == 1
        end
      else
        registros = registros.where(user_id: current_user.id)
        @user = current_user
      end

      # Filtro por ano/mês (substituiu o calendário De/Até) — o dropdown do
      # lado do cliente já não exibe ano/mês futuro, mas travamos aqui
      # também: um ano/mês além do atual não deve retornar registros
      # (não existe batida no futuro), então limitamos ao presente.
      if params[:ano].present?
        ano = params[:ano].to_i.clamp(..Time.current.year)

        if params[:mes].present?
          mes = params[:mes].to_i.clamp(1, 12)
          mes = [mes, Time.current.month].min if ano == Time.current.year

          inicio = Time.zone.local(ano, mes, 1).beginning_of_month
          fim = inicio.end_of_month
        else
          inicio = Time.zone.local(ano, 1, 1).beginning_of_year
          fim = ano == Time.current.year ? Time.current.end_of_month : Time.zone.local(ano, 12, 31).end_of_year
        end

        registros = registros.where(punched_at: inicio..fim)
      end

      @total = registros.count

      # Mês/ano exibidos no título do card "Registro Mensal" — usa o filtro
      # aplicado quando presente (mesmo clamp pro presente do filtro
      # principal), senão cai no mês/ano atual.
      @ano_titulo = params[:ano].present? ? params[:ano].to_i.clamp(..Time.current.year) : Time.current.year
      @mes_titulo = if params[:mes].present?
        m = params[:mes].to_i.clamp(1, 12)
        @ano_titulo == Time.current.year ? [m, Time.current.month].min : m
      else
        Time.current.month
      end

      # O card "Dia/Trabalhado/Registro/Informações" só faz sentido quando
      # já se sabe de qual usuário se está falando — um usuário básico só
      # vê os próprios registros (sempre "um usuário só"); um admin só entra
      # nesse modo depois de filtrar por um usuário específico. Sem isso,
      # o admin continua na visão agregada (Usuário/Data/Marcações).
      @modo_usuario_unico = !current_user.admin? || @user.present?

      if @modo_usuario_unico
        agrupado = registros.group_by { |r| r.punched_at.to_date }

        @daily_records = agrupado.sort_by { |data, _| data }
                                 .reverse
                                 .first(PER_PAGE)
                                 .map { |data, regs| montar_linha_dia(data, regs) }

        @resumo_mensal = calcular_resumo_mensal(@user, @ano_titulo, @mes_titulo)
      else
        agrupado = registros.group_by { |r| [r.punched_at.to_date, r.user_id] }

        @daily_records = agrupado.sort_by { |chave, _| chave }
                                 .reverse
                                 .first(PER_PAGE)
                                 .map { |(data, _user_id), regs|
          [data, regs.first.user, formatar_registro(regs)]
        }
      end
    end

    private

    # Junta os pares entrada-saída no formato "HH:MM-HH:MM, HH:MM-HH:MM"
    # já usado na coluna "Marcações"/"Registro". Marcação ímpar sem par
    # (entrada sem saída correspondente) aparece como "HH:MM-'---'".
    def formatar_registro(regs)
      pares = []
      regs.each_slice(2) do |par|
        entrada, saida = par
        pares << "#{I18n.l(entrada.punched_at, format: :short)}-#{saida ? I18n.l(saida.punched_at, format: :short) : '---'}"
      end
      pares.join(", ")
    end

    # Soma só os pares COMPLETOS de entrada-saída do dia. Marcação ímpar
    # sobrando (ex: 3 marcações — 1 par completo + 1 solta) é ignorada na
    # soma, exatamente como já é ignorada na formatação de "Registro".
    # Sem nenhum par completo, retorna "00:00:00" (dia em aberto).
    def calcular_trabalhado(regs)
      total_segundos = 0
      regs.each_slice(2) do |par|
        entrada, saida = par
        total_segundos += (saida.punched_at - entrada.punched_at).to_i if saida
      end
      formatar_duracao(total_segundos)
    end

    def montar_linha_dia(data, regs)
      dia_label = "#{data.day} #{I18n.t('date.abbr_day_names')[data.wday]}"
      [dia_label, calcular_trabalhado(regs), formatar_registro(regs), nil]
    end

    # Resumo mensal exibido no card "Registro Mensal". Só os campos que já
    # têm regra de negócio definida são calculados de verdade — o resto
    # (saldo inicial, meta mensal, saldo do mês, a cumprir, saldo
    # acumulado) depende de "meta mensal"/regime de trabalho, que ainda não
    # foi definido, então fica como placeholder até essa regra existir.
    def calcular_resumo_mensal(usuario, ano, mes)
      return nil unless usuario

      inicio_mes = Time.zone.local(ano, mes, 1).beginning_of_month
      fim_mes = inicio_mes.end_of_month
      hoje = Date.current
      ultimo_dia_considerado = (ano == hoje.year && mes == hoje.month) ? hoje : fim_mes.to_date

      registros_por_dia = TimeRecord.where(user_id: usuario.id, punched_at: inicio_mes..fim_mes)
                                     .order(:punched_at)
                                     .group_by { |r| r.punched_at.to_date }

      trabalhadas_segundos = 0
      presencas = 0
      ausencias = 0
      em_aberto = 0

      (inicio_mes.to_date..ultimo_dia_considerado).each do |dia|
        regs = registros_por_dia[dia] || []
        pares_completos = 0

        regs.each_slice(2) do |par|
          entrada, saida = par
          next unless saida

          trabalhadas_segundos += (saida.punched_at - entrada.punched_at).to_i
          pares_completos += 1
        end

        if pares_completos > 0
          presencas += pares_completos
        elsif dia == hoje
          # Marcação solta hoje (só entrada, sem saída ainda) fica "em
          # aberto" até a virada do dia — dia sem NENHUMA marcação ainda
          # não conta em nada, porque o dia ainda não terminou.
          em_aberto += 1 if regs.any?
        else
          # Dia já passou (não é mais hoje) sem nenhum par completo —
          # vira falta, mesmo que tenha tido uma marcação solta.
          ausencias += 1
        end
      end

      {
        saldo_inicial: "00:00:00",
        meta_mensal: "00:00:00",
        saldo_do_mes: "00:00:00",
        a_cumprir: "00:00:00",
        saldo_acumulado: "00:00:00",
        trabalhadas: formatar_duracao(trabalhadas_segundos),
        presencas: presencas,
        ausencias: ausencias,
        em_aberto: em_aberto
      }
    end
  end
end
