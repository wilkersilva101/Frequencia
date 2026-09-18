# Sprint 18 (task 18.1) — geração/atualização do `RelatorioFrequenciaFinal`
# (AG-5): relatório mensal consolidado com um `RelatorioFrequentador` por
# usuário. Portado de `RelatorioFrequenciaFinalServices.java`
# (`montarRelatorio`/`atualizarRelatorio`/`criarRelatorioFrequentador`,
# Intranet legada).
#
# Sprint 18 (task 18.3) — `valor_retroativo` deixou de ser fixo em 0: agora
# soma os `ValorRetroativo` reais do usuário no mês/ano via
# `ValorRetroativo.soma_do_mes` (`.sum(:numero_hora)`, sem a armadilha
# `cont=+valor` do legado — ver DUV-011 documentado no model
# `ValorRetroativo`). A fórmula do `resultado`, que tinha sido simplificada
# na task 18.1 assumindo `valor_retroativo` sempre 0
# (`saldo_bruto >= 0 ? 0 : saldo_bruto`), volta a ser a fórmula completa do
# legado: `saldo_bruto >= 0 ? valor_retroativo : saldo_bruto + valor_retroativo`.
class RelatorioFrequenciaFinalService
  def self.gerar(ano, mes, users: User.where.not(cpf: nil))
    new(ano, mes, users).gerar
  end

  def initialize(ano, mes, users)
    @ano = ano
    @mes = mes
    @users = users
  end

  # Idempotente: gerar de novo pro mesmo mês/ano atualiza o relatório
  # existente (recria os `RelatorioFrequentador` filhos do zero,
  # `data_alteracao` = agora) em vez de duplicar o relatório pai — mesmo
  # comportamento de `montarRelatorio`/`atualizarRelatorio` do legado. Não
  # há filtro de órgão (ver comentário do model `RelatorioFrequenciaFinal`).
  def gerar
    relatorio = RelatorioFrequenciaFinal.find_by(ano: @ano, mes: @mes)

    ActiveRecord::Base.transaction do
      if relatorio
        relatorio.update!(data_alteracao: Time.current)
        relatorio.relatorio_frequentadores.destroy_all
      else
        relatorio = RelatorioFrequenciaFinal.create!(ano: @ano, mes: @mes, data_geracao: Time.current)
      end

      @users.find_each do |user|
        relatorio.relatorio_frequentadores.create!(criar_relatorio_frequentador(user))
      end
    end

    relatorio
  end

  private

  # Portado de `criarRelatorioFrequentador` (linhas 86-103, legado), sem o
  # cálculo de `valor_retroativo` (ver nota de escopo acima). Lê o
  # `RegistroMensalFrequencia` já consolidado (AG-4) sem criar/recalcular
  # nada — se não existir ainda pro mês/ano, `saldo_bruto = 0`, mesmo
  # comportamento do legado (`registroMensal != null ? ... : 0`).
  def criar_relatorio_frequentador(user)
    registro_mensal = RegistroMensalFrequencia.find_by(user: user, ano: @ano, mes: @mes)
    saldo_bruto = registro_mensal&.saldo_bruto.to_i
    valor_retroativo = ValorRetroativo.soma_do_mes(user, @ano, @mes)
    resultado = saldo_bruto.negative? ? saldo_bruto + valor_retroativo : valor_retroativo

    {
      user: user,
      saldo_bruto: saldo_bruto,
      valor_retroativo: valor_retroativo,
      resultado: resultado
    }
  end
end
