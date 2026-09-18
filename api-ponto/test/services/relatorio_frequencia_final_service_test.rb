require "test_helper"

class RelatorioFrequenciaFinalServiceTest < ActiveSupport::TestCase
  def setup
    @user_um = users(:one)
    @user_dois = users(:two)
  end

  def criar_registro_mensal(user, saldo_bruto:, ano: 2026, mes: 9)
    trabalhado = saldo_bruto.positive? ? saldo_bruto : 0
    meta_mensal = saldo_bruto.negative? ? -saldo_bruto : 0
    RegistroMensalFrequencia.create!(
      user: user, ano: ano, mes: mes,
      data_inicio: Date.new(ano, mes, 1), data_fim: Date.new(ano, mes, 1).end_of_month,
      trabalhado: trabalhado, meta_mensal: meta_mensal
    )
  end

  test "gera relatorio com um RelatorioFrequentador por usuario" do
    relatorio = RelatorioFrequenciaFinalService.gerar(2026, 9, users: User.where(id: [ @user_um.id, @user_dois.id ]))

    assert relatorio.persisted?
    assert_equal 2026, relatorio.ano
    assert_equal 9, relatorio.mes
    assert_not_nil relatorio.data_geracao
    assert_nil relatorio.data_alteracao
    assert_equal 2, relatorio.relatorio_frequentadores.count
  end

  test "gerar de novo para o mesmo mes/ano atualiza em vez de duplicar" do
    RelatorioFrequenciaFinalService.gerar(2026, 9, users: User.where(id: @user_um.id))
    assert_equal 1, RelatorioFrequenciaFinal.where(ano: 2026, mes: 9).count

    relatorio = RelatorioFrequenciaFinalService.gerar(2026, 9, users: User.where(id: @user_um.id))

    assert_equal 1, RelatorioFrequenciaFinal.where(ano: 2026, mes: 9).count
    assert_not_nil relatorio.data_alteracao
    assert_equal 1, relatorio.relatorio_frequentadores.count
  end

  test "resultado eh zero quando saldo bruto positivo e sem valor retroativo" do
    criar_registro_mensal(@user_um, saldo_bruto: 3600)

    relatorio = RelatorioFrequenciaFinalService.gerar(2026, 9, users: User.where(id: @user_um.id))
    frequentador = relatorio.relatorio_frequentadores.first

    assert_equal 3600, frequentador.saldo_bruto
    assert_equal 0, frequentador.valor_retroativo
    assert_equal 0, frequentador.resultado
  end

  # Sprint 18 (task 18.3) — valor_retroativo deixou de ser fixo em 0: soma
  # real dos ValorRetroativo do usuario no mes/ano. Com saldo_bruto
  # positivo, resultado = valor_retroativo (nao mais sempre 0).
  test "resultado eh igual ao valor retroativo quando saldo bruto positivo" do
    criar_registro_mensal(@user_um, saldo_bruto: 3600)
    ValorRetroativo.create!(user: @user_um, ano: 2026, mes: 9, data_geracao: Time.current, numero_hora: 5)
    ValorRetroativo.create!(user: @user_um, ano: 2026, mes: 9, data_geracao: Time.current, numero_hora: 7)

    relatorio = RelatorioFrequenciaFinalService.gerar(2026, 9, users: User.where(id: @user_um.id))
    frequentador = relatorio.relatorio_frequentadores.first

    assert_equal 3600, frequentador.saldo_bruto
    # soma real dos 2 ValorRetroativo (5 + 7 = 12), nao so o ultimo (7) —
    # prova que o bug DUV-011 do legado nao foi replicado aqui.
    assert_equal 12, frequentador.valor_retroativo
    assert_equal 12, frequentador.resultado
  end

  # Cenario com saldo negativo e valor_retroativo != 0: resultado deve ser
  # a soma dos dois (saldo_bruto + valor_retroativo), formula completa do
  # legado agora que valor_retroativo nao eh mais sempre 0.
  test "resultado soma saldo bruto negativo com valor retroativo" do
    criar_registro_mensal(@user_um, saldo_bruto: -1800)
    ValorRetroativo.create!(user: @user_um, ano: 2026, mes: 9, data_geracao: Time.current, numero_hora: 3)
    ValorRetroativo.create!(user: @user_um, ano: 2026, mes: 9, data_geracao: Time.current, numero_hora: 4)
    ValorRetroativo.create!(user: @user_um, ano: 2026, mes: 9, data_geracao: Time.current, numero_hora: 5)

    relatorio = RelatorioFrequenciaFinalService.gerar(2026, 9, users: User.where(id: @user_um.id))
    frequentador = relatorio.relatorio_frequentadores.first

    assert_equal(-1800, frequentador.saldo_bruto)
    assert_equal 12, frequentador.valor_retroativo
    assert_equal(-1800 + 12, frequentador.resultado)
  end

  test "resultado eh zero quando saldo bruto zero" do
    criar_registro_mensal(@user_um, saldo_bruto: 0)

    relatorio = RelatorioFrequenciaFinalService.gerar(2026, 9, users: User.where(id: @user_um.id))
    frequentador = relatorio.relatorio_frequentadores.first

    assert_equal 0, frequentador.saldo_bruto
    assert_equal 0, frequentador.resultado
  end

  test "resultado eh igual ao saldo bruto quando negativo" do
    criar_registro_mensal(@user_um, saldo_bruto: -1800)

    relatorio = RelatorioFrequenciaFinalService.gerar(2026, 9, users: User.where(id: @user_um.id))
    frequentador = relatorio.relatorio_frequentadores.first

    assert_equal(-1800, frequentador.saldo_bruto)
    assert_equal(-1800, frequentador.resultado)
  end

  test "usuario sem RegistroMensalFrequencia no mes entra com saldo_bruto e resultado zero" do
    relatorio = RelatorioFrequenciaFinalService.gerar(2026, 9, users: User.where(id: @user_um.id))
    frequentador = relatorio.relatorio_frequentadores.first

    assert_equal 0, frequentador.saldo_bruto
    assert_equal 0, frequentador.resultado
  end

  # --- Task 18.4 — auditoria de cobertura: geração idempotente -------------
  #
  # Gap identificado: o teste "gerar de novo para o mesmo mes/ano atualiza em
  # vez de duplicar" (18.1) prova só a não-duplicação do relatório pai (a
  # contagem de `RelatorioFrequenciaFinal`/`RelatorioFrequentador` continua
  # 1). Nenhum teste existente prova que a 2ª geração reflete um
  # `RegistroMensalFrequencia` que MUDOU entre a 1ª e a 2ª rodada — o cenário
  # real é: mês consolidado, relatório gerado (1ª rodada), depois um
  # retificador é aplicado via `ConsolidacaoMensalService.aplicar_retificador`
  # (mesmo em mês finalizado, task 18.2), e o relatório é gerado de novo (2ª
  # rodada). Se a 2ª geração reaproveitasse os `RelatorioFrequentador` velhos
  # em vez de recriá-los do zero, os valores da 1ª rodada ficariam
  # "congelados" incorretamente — o service já faz `destroy_all` +
  # recriação (linha 37 de `relatorio_frequencia_final_service.rb`), mas
  # isso nunca foi provado por teste até aqui.
  test "gerar de novo reflete saldo_bruto e valor_retroativo atualizados entre a 1a e a 2a geracao, nao os valores congelados da 1a rodada" do
    regime = Regime.create!(
      nome: "Jornada", modalidade: "HORAS", limite_credito: 10, limite_debito: 10,
      expediente: [ { "dias" => "SEG,TER,QUA,QUI,SEX,", "inicio" => "08:00", "fim" => "12:00" } ]
    )
    RegimeFrequentador.create!(user: @user_um, regime: regime, momento_inicial: Date.new(2026, 8, 1), tipo: RegimeFrequentador::OFICIAL)
    CalculoDiario.create!(
      user: @user_um, data: Date.new(2026, 9, 1),
      meta_segundos: 4 * 3600, normal_segundos: 4 * 3600, total_segundos: 4 * 3600,
      excepcional_segundos: 0, falta: false, aberto: false
    )
    ConsolidacaoMensalService.consolidar(@user_um, 2026, 9, hoje: Date.new(2026, 9, 30))

    # 1a geração: saldo bruto 0 (trabalhado == meta_mensal), sem valor
    # retroativo ainda.
    relatorio = RelatorioFrequenciaFinalService.gerar(2026, 9, users: User.where(id: @user_um.id))
    frequentador_primeira_rodada = relatorio.relatorio_frequentadores.first
    assert_equal 0, frequentador_primeira_rodada.saldo_bruto
    assert_equal 0, frequentador_primeira_rodada.valor_retroativo
    assert_equal 0, frequentador_primeira_rodada.resultado

    # Entre a 1a e a 2a rodada: mês finalizado, um retificador de crédito
    # aplicado via `aplicar_retificador` (task 18.2, funciona pós-fechamento
    # — não muda `saldo_bruto`, que é `trabalhado - meta_mensal`, mas prova
    # que o mês pode ser mexido depois de fechado) e um `ValorRetroativo`
    # lançado (task 18.3) — nenhum dos dois existia na 1a geração.
    RegistroMensalFrequencia.find_by(user: @user_um, ano: 2026, mes: 9).finalizar!
    RetificadorBancoHoras.create!(
      user: @user_um, ano: 2026, mes: 9,
      tipo: RetificadorBancoHoras::CREDITO_POR_TRABALHO_EXCEPCIONAL, segundos_a_retificar: 2 * 3600
    )
    ConsolidacaoMensalService.aplicar_retificador(@user_um, 2026, 9)
    ValorRetroativo.create!(user: @user_um, ano: 2026, mes: 9, data_geracao: Time.current, numero_hora: 6)

    # 2a geração: mesmo relatório pai (sem duplicar), mas o
    # RelatorioFrequentador filho deve refletir o valor_retroativo/resultado
    # ATUALIZADO (6, não mais 0) — prova que a 2a rodada reconsulta
    # `ValorRetroativo.soma_do_mes`/`RegistroMensalFrequencia` do zero
    # (via `destroy_all` + recriação), não reaproveita os valores
    # "congelados" da 1a rodada.
    assert_no_difference -> { RelatorioFrequenciaFinal.where(ano: 2026, mes: 9).count } do
      relatorio_2a_rodada = RelatorioFrequenciaFinalService.gerar(2026, 9, users: User.where(id: @user_um.id))
      assert_equal relatorio.id, relatorio_2a_rodada.id
      assert_equal 1, relatorio_2a_rodada.relatorio_frequentadores.count

      frequentador_2a_rodada = relatorio_2a_rodada.relatorio_frequentadores.first
      assert_not_equal frequentador_primeira_rodada.id, frequentador_2a_rodada.id # recriado do zero, não reaproveitado
      assert_equal 0, frequentador_2a_rodada.saldo_bruto # trabalhado/meta_mensal continuam congelados pela finalização
      assert_equal 6, frequentador_2a_rodada.valor_retroativo # atualizado, não os 0 congelados da 1a rodada
      assert_equal 6, frequentador_2a_rodada.resultado
    end
  end

  test "indice unico em ano e mes do RelatorioFrequenciaFinal impede duplicata" do
    RelatorioFrequenciaFinal.create!(ano: 2026, mes: 9, data_geracao: Time.current)

    duplicado = RelatorioFrequenciaFinal.new(ano: 2026, mes: 9, data_geracao: Time.current)
    assert_raises(ActiveRecord::RecordInvalid) { duplicado.save! }
  end
end
