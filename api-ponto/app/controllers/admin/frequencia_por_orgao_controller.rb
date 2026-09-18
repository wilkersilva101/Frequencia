module Admin
  class FrequenciaPorOrgaoController < Admin::ApplicationController
    include DuracaoFormatavel

    def index
      # Task 23.7 — CanCanCan: autorização explícita para leitura.
      # Admin/gestor/operador podem visualizar (todos têm :read em :all).
      authorize! :read, :all

      @registros = registros_por_orgao
    end

    private

    # Agregação (Fase A + motor de cálculo, Sprint 16/17):
    # - "Presenças": dias distintos com pelo menos 1 batida no período
    # - "Ausências": afastamentos (AfastamentoCache, Sprint 12) que começam
    #   no período
    # - "Trabalhado": soma de `CalculoDiario#total_segundos` dos usuários do
    #   órgão no período filtrado (task 17.3). `CalculoDiario` só existe pra
    #   quem já teve `CalculoDiarioService.calcular` rodado (não há
    #   job/gatilho automático ainda, decisão própria fora de escopo aqui) —
    #   sem nenhum registro calculado no período, continua "—", mesma
    #   disciplina de não inventar dado ausente.
    # Pedido do usuário (2026-09-02): trocar leitura de espelho local
    # (`FrequentadorCache`) por SELECT ao vivo no pessoas2 — órgão vem da
    # lotação principal vigente de vínculo ativo (Pessoas::Vinculo).
    def registros_por_orgao
      orgaos = Pessoas::Vinculo.orgaos_em_uso

      if params[:orgao].present?
        orgaos = orgaos.select { |orgao| orgao.downcase.include?(params[:orgao].downcase) }
      end

      orgaos.map { |orgao| linha_do_orgao(orgao) }
    end

    def linha_do_orgao(orgao)
      cpfs = Pessoas::Vinculo.cpfs_por_orgao(orgao)
      user_ids = User.where(cpf: cpfs).pluck(:id)

      {
        orgao: orgao,
        trabalhado: trabalhado_calculado(user_ids),
        presencas: contar_dias_com_batida(user_ids),
        ausencias: contar_afastamentos(cpfs)
      }
    end

    def trabalhado_calculado(user_ids)
      calculos = CalculoDiario.where(user_id: user_ids)
      calculos = filtrar_por_periodo(calculos, :data)
      return nil unless calculos.exists?

      formatar_duracao(calculos.sum(:total_segundos))
    end

    def contar_dias_com_batida(user_ids)
      registros = TimeRecord.where(user_id: user_ids)
      registros = filtrar_por_periodo(registros, :punched_at)
      registros.pluck(:user_id, Arel.sql("DATE(punched_at)")).uniq.size
    end

    def contar_afastamentos(cpfs)
      afastamentos = AfastamentoCache.where(cpf: cpfs)
      afastamentos = filtrar_por_periodo(afastamentos, :momento_inicial)
      afastamentos.count
    end

    def filtrar_por_periodo(relation, coluna)
      relation = relation.where("EXTRACT(MONTH FROM #{coluna}) = ?", params[:mes]) if params[:mes].present?
      relation = relation.where("EXTRACT(YEAR FROM #{coluna}) = ?", params[:ano]) if params[:ano].present?
      relation
    end
  end
end
