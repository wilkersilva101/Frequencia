class Regime < ApplicationRecord
  # AG-2 (docs/PRD-FREQUENCIA.md §4.2) — agregado forte de jornada/período.
  # Estrutura trazida da Intranet legada (Regime.java,
  # ConfiguracaoFrequencia.java) em 2026-08-31 — a Intranet será
  # descomissionada e o Frequencia precisa ser autossuficiente com as
  # mesmas regras de negócio. Ver docs/01-inventario/02-regime-jornada.md.
  #
  # Escopo desta etapa: só estrutura/schema. O motor de cálculo que usa
  # esses campos (metaSemanal, periodosSemana, banco de horas) fica para
  # a Fase B (Sprints 16+) — ver decisão registrada no SPRINT-PLAN.md.
  #
  # NÃO replica o bug conhecido do legado (Q4, ConfiguracaoFrequencia#clone
  # copia limiteCredito em limiteDebito) — aqui não existe lógica de clone.

  # Códigos reais de `presenca_regime_categoriavinculo` — confirmados em
  # 2026-08-31 consultando o banco de produção da Intranet (`SELECT DISTINCT
  # categoria`, todos os 309 regimes, não só os ativos): 6 desses códigos
  # são usados de fato nos regimes já importados; `RESIDENTE` foi
  # adicionado a pedido do usuário (2026-09-02) como categoria nova
  # disponível — existe no enum real do legado (`CategoriaVinculoEnum.java`)
  # mas nunca esteve vinculada a um regime até agora, então nenhum dos 309
  # regimes importados tem essa categoria (fica disponível pra uso daqui
  # pra frente).
  CATEGORIAS_DISPONIVEIS = %w[
    SERVIDOR_CARREIRA
    CARGO_COMISSIONADO
    ESTAGIARIO
    RESIDENTE
    TERCEIRIZADO
    AUXILIAR_DA_JUSTICA
    CEDIDO
  ].freeze

  # `enums/Modalidade.java` do legado. Confirmado em 2026-08-31 no banco de
  # produção: `HORAS` (285) e `OCORRENCIAS` (24) são os únicos valores
  # realmente usados nos 309 regimes — `HORAS_COM_INTERVALO` nunca aparece
  # em nenhum registro, o que confirma (sem resolver o "porquê") a dúvida Q1
  # da doc de engenharia reversa: existe e é calculável, mas não é usada na
  # prática. Mantida na lista pois é um valor válido do enum/motor de
  # cálculo, só não tem uso real observado.
  MODALIDADES_DISPONIVEIS = %w[HORAS HORAS_COM_INTERVALO OCORRENCIAS].freeze

  # Só para exibição (dropdown, listagem) — o valor persistido é sempre o
  # código real (`CATEGORIAS_DISPONIVEIS`), nunca o rótulo. Rótulos
  # atualizados a pedido do usuário (2026-09-02).
  CATEGORIAS_LABELS = {
    "SERVIDOR_CARREIRA" => "Servidor Efetivo",
    "CARGO_COMISSIONADO" => "Servidor Comissionado",
    "ESTAGIARIO" => "Estagiário",
    "RESIDENTE" => "Residente",
    "TERCEIRIZADO" => "Terceirizado",
    "AUXILIAR_DA_JUSTICA" => "Auxiliar de justiça",
    "CEDIDO" => "Cedido"
  }.freeze

  # Idem, para modalidade — o valor persistido continua sendo o código real.
  MODALIDADES_LABELS = {
    "HORAS" => "Horas",
    "HORAS_COM_INTERVALO" => "Horas com intervalo",
    "OCORRENCIAS" => "Ocorrências"
  }.freeze

  has_many :regime_frequentadores, dependent: :restrict_with_exception
  has_many :users, through: :regime_frequentadores
  has_many :regime_categorias, dependent: :destroy

  belongs_to :anterior, class_name: "Regime", optional: true
  belongs_to :padrao, class_name: "Regime", optional: true

  validates :nome, presence: true
  validates :modalidade, inclusion: { in: MODALIDADES_DISPONIVEIS }, allow_nil: true

  def categorias
    regime_categorias.map(&:categoria)
  end

  # Formatação de dias/horários pra coluna "Resumo" — mesmo formato do
  # legado (`Regime.java#getResumo()`: "{dias} de {inicio} às {fim}", um
  # item por período de `expediente`). É só formatação de exibição, não o
  # motor de cálculo (metaSemanal/banco de horas) — isso continua Fase B.
  # `resumo` (campo digitado manualmente no form) tem prioridade quando
  # presente; senão computa a partir do `expediente` real.
  def resumo_exibicao
    return [ resumo ] if resumo.present?

    Array(expediente).map do |periodo|
      "#{periodo['dias']} de #{periodo['inicio']} às #{periodo['fim']}"
    end
  end

  def categorias=(lista)
    self.regime_categorias = Array(lista).reject(&:blank?).map { |categoria| RegimeCategoria.new(categoria: categoria) }
  end

  # --- Motor de cálculo (Sprint 16, task 16.2) ---------------------------
  # Portado de `intranet/src/modules/presenca/beans/Regime.java` e
  # `Horario.java` — só os métodos que o `Regime` calcula sozinho a partir
  # do próprio `expediente` (dado estático da jornada). Orquestração contra
  # `TimeRecord`/`Dia`/`CalculoDiario` de uma pessoa num dia real é escopo
  # da task 16.3, não implementada aqui.

  # `Regime.java:390-400` — soma, por período do `expediente`, a meta
  # semanal em minutos. Modalidade HORAS: minutos/dia × dias da semana.
  # OCORRENCIAS/HORAS_COM_INTERVALO: conta só nº de dias (Horario.java:91-98).
  def meta_semanal_em_minutos
    Array(expediente).sum { |periodo| meta_semanal_periodo(periodo) }
  end

  # `Regime.java:401-414` — mesma soma de `meta_semanal_em_minutos`, mas
  # quando a modalidade é OCORRENCIAS o legado força o cálculo como se
  # fosse HORAS (`h.metaSemanal(Modalidade.HORAS)`) em vez da modalidade
  # real do regime — usado no legado só pra exibir a meta em milissegundos,
  # mesmo em regime de ocorrência. Portado por completude/paridade com o
  # legado, mas não há, até esta task, nenhum consumidor real no Frequencia
  # que precise do valor em milissegundos — a exibição (`getMetaSemanalFormatada`,
  # portado como `meta_semanal_formatada` abaixo) usa a versão em minutos.
  # Dúvida em aberto: se surgir necessidade real de milissegundos (ex:
  # paridade de payload com o legado na 16.4), este método já está pronto.
  def meta_semanal_em_milissegundos
    Array(expediente).sum { |periodo| meta_semanal_periodo(periodo, modalidade: "HORAS") } * 60 * 1000
  end

  # `Regime.java:375-388` — formata a meta semanal calculada (a partir do
  # `expediente`) como string de exibição. Não confundir com o campo
  # `meta_semanal` (string digitada manualmente no form, hoje usada como
  # fallback em telas existentes) nem com `resumo_exibicao` (que formata
  # os *períodos* como "dias de X às Y" — aqui formatamos o *total*
  # calculado da semana, ex: "40h", "7,5h" ou, em OCORRENCIAS, "5").
  def meta_semanal_formatada
    minutos = meta_semanal_em_minutos

    return minutos.to_i.to_s if modalidade == "OCORRENCIAS"

    horas = minutos / 60.0
    horas_truncadas = horas.truncate

    if horas == horas_truncadas
      "#{horas_truncadas}h"
    else
      "#{format('%.2f', horas).sub('.', ',').sub(/0$/, '')}h"
    end
  end

  # `Regime.java:153-172` (periodosSemana) + `176-208` (getHorariosDaSemana)
  # — agrupa os períodos do `expediente` por dia da semana individual.
  # Retorna um Hash { wday (0=domingo..6=sábado, convenção de `Date#wday`,
  # equivalente direto ao `DiaSemanaEnum` do legado sem o +1 do
  # `Calendar.DAY_OF_WEEK`) => [ { "inicio" => ..., "fim" => ... }, ... ] }.
  def periodos_por_dia_da_semana
    mapa = Hash.new { |hash, chave| hash[chave] = [] }

    Array(expediente).each do |periodo|
      dias_do_periodo(periodo).each do |wday|
        mapa[wday] << { "inicio" => periodo["inicio"], "fim" => periodo["fim"] }
      end
    end

    mapa
  end

  private

  # Mapeamento de sigla de dia (usado na string `dias` do `expediente`,
  # separada por vírgula, ex: "SEG,TER,QUA,QUI,SEX,") para `wday` do Ruby
  # (0=domingo..6=sábado — mesma convenção de `DiaSemanaEnum.java`, sem o
  # +1 do `java.util.Calendar`).
  SIGLAS_DIA_SEMANA = {
    "DOM" => 0, "SEG" => 1, "TER" => 2, "QUA" => 3,
    "QUI" => 4, "SEX" => 5, "SAB" => 6
  }.freeze

  def dias_do_periodo(periodo)
    quantidade_de_dias_strings(periodo).filter_map { |sigla| SIGLAS_DIA_SEMANA[sigla] }
  end

  # `DiaSemanaEnum.java:115-118` — `dias.split(",")`, descartando strings
  # vazias resultantes (a string real do `expediente` sempre termina em
  # vírgula sobrando, ex: "SEG,TER,QUA,QUI,SEX,").
  def quantidade_de_dias_strings(periodo)
    periodo["dias"].to_s.split(",").reject(&:blank?)
  end

  def quantidade_de_dias(periodo)
    quantidade_de_dias_strings(periodo).size
  end

  # `Horario.java:99-103` — diferença em minutos entre "inicio" e "fim"
  # (strings "HH:MM").
  def meta_diaria_em_minutos(periodo)
    inicio = periodo["inicio"].to_s
    fim = periodo["fim"].to_s
    return 0 if inicio.blank? || fim.blank?

    inicio_minutos = minutos_desde_meia_noite(inicio)
    fim_minutos = minutos_desde_meia_noite(fim)
    fim_minutos - inicio_minutos
  end

  def minutos_desde_meia_noite(horario)
    hora, minuto = horario.split(":").map(&:to_i)
    (hora * 60) + minuto
  end

  # `Horario.java:91-98` — meta semanal de um único período do `expediente`,
  # dada a modalidade (por padrão, a do próprio regime; `meta_semanal_em_milissegundos`
  # passa "HORAS" explicitamente pra forçar o cálculo em minutos mesmo em
  # regime de OCORRENCIAS, replicando o comportamento do legado).
  def meta_semanal_periodo(periodo, modalidade: self.modalidade)
    if modalidade == "HORAS"
      meta_diaria_em_minutos(periodo) * quantidade_de_dias(periodo)
    else
      quantidade_de_dias(periodo)
    end
  end
end
