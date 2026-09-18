require "test_helper"

# Sprint 16 (task 16.4) — testes de paridade entre `CalculoDiarioService`
# (motor simplificado da 16.3) e o resultado REAL já calculado pelo motor
# v2 do legado (`presenca_calculodiario`, banco MySQL de produção,
# 10.254.3.6). Objetivo: medir a fidelidade do motor simplificado, não
# completá-lo — divergências encontradas são documentadas, não escondidas.
#
# Metodologia (ver nota da 16.4 no SPRINT-PLAN.md para o detalhe das
# consultas SQL usadas para achar os candidatos): casos "limpos" —
# `excepcional = 0`, `informacao` vazia, `aberto = 0`, `ausencia = 0`,
# `modalidade = 'HORAS'`, data recente (2025-09-17, quarta-feira, dentro
# das janelas SEG-SEX de todos os regimes usados aqui), e — crucialmente —
# exatamente 1 `RegimeFrequentador` vigente na data (sem ambiguidade de
# precedência) resolvido manualmente contra `presenca_regimefrequentador`.
#
# Unidade confirmada por inspeção direta do dado real: `meta`/`normal`/
# `total` em `presenca_calculodiario` estão em SEGUNDOS (ex: regime
# "08:00 às 13:00" = 5h = 18000, bate exatamente com o `meta` real) — mesma
# unidade de `CalculoDiario#meta_segundos`/`#total_segundos` no Frequencia,
# comparação direta sem conversão.
#
# Identificação dos frequentadores mantida apenas pelo `frequentador_id`
# numérico do legado (sem CPF/nome) — exigido pela tarefa.
class CalculoDiarioServiceParidadeTest < ActiveSupport::TestCase
  QUARTA = Date.new(2025, 9, 17)

  def criar_regime(inicio:, fim:)
    Regime.create!(
      nome: "Regime real (paridade legado)",
      modalidade: "HORAS",
      expediente: [ { "dias" => "SEG,TER,QUA,QUI,SEX", "inicio" => inicio, "fim" => fim } ]
    )
  end

  def vincular(user, regime)
    RegimeFrequentador.create!(user: user, regime: regime, momento_inicial: QUARTA - 30, tipo: RegimeFrequentador::OFICIAL)
  end

  def bater(user, momento)
    TimeRecord.create!(user: user, punched_at: momento, raw_data: "paridade-legado", authentication_mode: "manual")
  end

  # --- Caso real 1: frequentador_id 8218 ------------------------------
  # Regime único vigente: OFICIAL, HORAS, 08:00-13:00 (meta real = 18000s).
  # Marcações reais: ENTRADA 07:22:34, SAIDA 12:22:22 (diferença = 17988s,
  # ABAIXO da meta — nenhuma regra de banco de horas/carência entra em
  # jogo). Legado real: normal = total = 17988.
  test "paridade frequentador_id 8218: HORAS, duas marcacoes, trabalhado abaixo da meta bate exatamente" do
    user = User.create!(nome_completo: "Paridade 8218", username: "paridade.8218", password: "123456", status: 1)
    regime = criar_regime(inicio: "08:00", fim: "13:00")
    vincular(user, regime)
    bater(user, Time.zone.local(2025, 9, 17, 7, 22, 34))
    bater(user, Time.zone.local(2025, 9, 17, 12, 22, 22))

    resultado = CalculoDiarioService.calcular(user, QUARTA)

    assert_equal 18_000, resultado.meta_segundos, "meta real do legado: 18000s (5h, regime 08:00-13:00)"
    assert_equal 17_988, resultado.total_segundos, "total real do legado: 17988s — motor simplificado bate exatamente"
  end

  # --- Caso real 2: frequentador_id 7303 ------------------------------
  # Mesmo regime (OFICIAL, HORAS, 08:00-13:00). Marcações reais: ENTRADA
  # 07:23:59, SAIDA 12:18:53 (diferença = 17694s, também abaixo da meta).
  # Legado real: normal = total = 17694.
  test "paridade frequentador_id 7303: HORAS, duas marcacoes, trabalhado abaixo da meta bate exatamente" do
    user = User.create!(nome_completo: "Paridade 7303", username: "paridade.7303", password: "123456", status: 1)
    regime = criar_regime(inicio: "08:00", fim: "13:00")
    vincular(user, regime)
    bater(user, Time.zone.local(2025, 9, 17, 7, 23, 59))
    bater(user, Time.zone.local(2025, 9, 17, 12, 18, 53))

    resultado = CalculoDiarioService.calcular(user, QUARTA)

    assert_equal 18_000, resultado.meta_segundos
    assert_equal 17_694, resultado.total_segundos, "total real do legado: 17694s — motor simplificado bate exatamente"
  end

  # --- Caso real 3: frequentador_id 8106 — DIVERGÊNCIA ESPERADA -------
  # Mesmo regime (OFICIAL, HORAS, 08:00-13:00, meta real = 18000s).
  # Marcações reais: ENTRADA 07:22:09, SAIDA 12:27:20 — diferença bruta =
  # 18311s, ACIMA da meta. Legado real: normal = total = 18000 (== meta,
  # não 18311).
  #
  # Divergência confirmada e não é ruído: o mesmo padrão aparece em outros
  # 2 frequentadores reais do mesmo dia com o mesmo regime (8279: bruto
  # 19845s → legado grava 18000; frequentador 6137, regime diferente:
  # bruto 9051s vs meta 9000s → legado grava 9000s). O motor v2 real
  # SEMPRE limita `normal`/`total` à meta do dia quando o trabalhado bruto
  # excede a meta — isso é precisamente o mecanismo de banco de
  # horas/hora-extra (`permitidoAcumularHoras`/limite de crédito de
  # `Regime#configuracao`) que a nota de escopo da 16.3 lista
  # explicitamente como NÃO portado (Sprint 17: banco de horas/acúmulo de
  # saldo entre dias). `CalculoDiarioService::PrimeiraEntradaUltimaSaida`
  # não faz esse cap — usa a diferença bruta primeira/última marcação.
  #
  # Asserção reflete o comportamento REAL do motor simplificado (não o do
  # legado) — a diferença é o valor esperado e documentado, não escondida.
  test "paridade frequentador_id 8106: trabalhado bruto acima da meta diverge do legado (cap de banco de horas nao portado, Sprint 17)" do
    user = User.create!(nome_completo: "Paridade 8106", username: "paridade.8106", password: "123456", status: 1)
    regime = criar_regime(inicio: "08:00", fim: "13:00")
    vincular(user, regime)
    bater(user, Time.zone.local(2025, 9, 17, 7, 22, 9))
    bater(user, Time.zone.local(2025, 9, 17, 12, 27, 20))

    resultado = CalculoDiarioService.calcular(user, QUARTA)

    assert_equal 18_000, resultado.meta_segundos
    # Legado real: total = 18000 (capado na meta). Motor simplificado: usa
    # a diferença bruta (18311s) — divergência esperada e documentada.
    assert_equal 18_311, resultado.total_segundos, "diverge do legado real (18000s, capado na meta) por nao portar o cap de banco de horas — Sprint 17"
  end

  # --- Caso real 4: frequentador_id 7698 — DIVERGÊNCIA ESPERADA -------
  # Mesmo regime (OFICIAL, HORAS, 08:00-13:00, meta real = 18000s).
  # Marcações reais do dia (3, não 2): ENTRADA 07:04:55, SAIDA 11:18:48,
  # INDEFINIDO 12:22:00. Legado real pareia especificamente ENTRADA↔SAIDA
  # (ignora a 3a marcação "INDEFINIDO"): normal = total = 15233
  # (11:18:48 - 07:04:55).
  #
  # `CalculoDiarioService::PrimeiraEntradaUltimaSaida` (16.3) foi
  # deliberadamente especificado como "diferença entre a PRIMEIRA e a
  # ÚLTIMA marcação do dia" (nota da 16.3, SPRINT-PLAN.md), sem filtrar
  # por tipo de operação — logo aqui usa 12:22:00 (última marcação
  # cronológica, não a SAIDA real) menos 07:04:55 = 19025s.
  #
  # Classificado como (a): simplificação já deliberada na 16.3 (não um bug
  # novo desta task) — o teste documenta o valor real que o motor
  # simplificado produz, não o do legado.
  test "paridade frequentador_id 7698: marcacao extra fora do par entrada/saida diverge do legado (16.3 usa 1a/ultima marcacao, nao pareamento por tipo)" do
    user = User.create!(nome_completo: "Paridade 7698", username: "paridade.7698", password: "123456", status: 1)
    regime = criar_regime(inicio: "08:00", fim: "13:00")
    vincular(user, regime)
    bater(user, Time.zone.local(2025, 9, 17, 7, 4, 55))
    bater(user, Time.zone.local(2025, 9, 17, 11, 18, 48))
    bater(user, Time.zone.local(2025, 9, 17, 12, 22, 0))

    resultado = CalculoDiarioService.calcular(user, QUARTA)

    assert_equal 18_000, resultado.meta_segundos
    # Legado real: total = 15233 (pareia ENTRADA 07:04:55 com SAIDA
    # 11:18:48, ignora a 3a marcação). Motor simplificado: primeira/última
    # marcação cronológica (12:22:00 - 07:04:55) = 19025s — divergência
    # esperada e documentada (simplificação já deliberada na 16.3).
    assert_equal 19_025, resultado.total_segundos, "diverge do legado real (15233s, pareado por ENTRADA/SAIDA) por usar 1a/ultima marcacao sem filtrar tipo — simplificacao deliberada da 16.3"
  end
end
