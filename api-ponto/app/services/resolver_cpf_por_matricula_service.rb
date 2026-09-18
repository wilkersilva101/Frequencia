# Resolve matrícula(s) em CPF a partir da folha de uma competência do
# GestoRH — lida diretamente da tabela `gestorh_contracheque_mirrors` do
# banco do Pessoas (task 8.13), que é o mesmo espelho local que alimentava
# `SticapiClient::Gestorh.competencia(mes:, ano:)` via HTTP. Necessário
# porque a listagem de servidores de uma unidade (Pessoas::Lotacao) não
# traz CPF, só matrícula (a tabela `pessoas` é que tem `cpf`, e o vínculo
# entre matrícula-da-folha e pessoa só existe garantidamente dentro de uma
# competência específica).
#
# Não persiste a competência inteira (~4700 registros) no banco do
# Frequencia — o mapa matricula => cpf vive só na memória da instância
# (escopo de um job).
class ResolverCpfPorMatriculaService
  def self.call(matriculas, mes:, ano:)
    new(mes: mes, ano: ano).call(matriculas)
  end

  # "Competência mais recente" sem hardcode de mês/ano: tenta o mês atual e
  # o mês anterior, mesclando os dois (mês atual tem prioridade quando a
  # matrícula aparece nos dois). Não usa "mês atual vazio? cai pro
  # anterior" simples porque uma competência existir não garante que ela
  # contenha TODAS as matrículas pedidas (ex.: servidor recém-lotado que
  # ainda não caiu na folha do mês atual, mas está na do mês anterior) —
  # ver achado registrado no SPRINT-PLAN.md, Sprint 10B (matrícula do
  # próprio usuário não apareceu na competência de jul/2026).
  def self.mais_recente(matriculas)
    hoje = Time.zone.today
    mes_anterior = hoje.prev_month

    resultado_anterior = call(matriculas, mes: mes_anterior.month, ano: mes_anterior.year)
    resultado_atual = call(matriculas, mes: hoje.month, ano: hoje.year)

    resultado_anterior.merge(resultado_atual)
  end

  def initialize(mes:, ano:)
    @mes = mes
    @ano = ano
  end

  # Retorna um Hash { "matricula" => "cpf" } só com as matrículas pedidas
  # que foram encontradas na competência. Matrícula não encontrada
  # simplesmente não aparece no retorno (chamador decide o que fazer).
  def call(matriculas)
    matriculas_normalizadas = matriculas.map(&:to_s)
    mapa_completo.slice(*matriculas_normalizadas)
  end

  private

  # Não filtramos por `orgao_id`: o pessoas2 tem múltiplas competências
  # (uma por órgão) para o mesmo mês/ano, mas a chamada Sticapi original
  # também não recebia/filtrava por órgão (a API já respondia escopada).
  # Ver nota em app/models/pessoas/competencia.rb.
  def mapa_completo
    @mapa_completo ||= Pessoas::GestorhContrachequeMirror.pares_matricula_cpf_para(mes: @mes, ano: @ano)
      .each_with_object({}) do |(matricula, cpf), memo|
        memo[matricula.to_s] = cpf if matricula.present? && cpf.present?
      end
  end
end
