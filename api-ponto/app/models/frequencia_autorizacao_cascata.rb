# Tarefa 29.7 (Sprint 29) — rollout da cascata de autorização de frequência.
#
# A cascata em si vive na `AutorizacaoFrequencia` (29.4, PORO de consulta) e no
# `FrequentadoresVisiveis` (29.6, irmão SQL). Esta classe NÃO decide acesso:
# ela só responde "o rollout está ligado?" e emite o log de auditoria —
# `EVENTO_SHADOW` (decisão PROJETADA do modo shadow) e `EVENTO_NEGACAO`
# (negação EFETIVA do modo `:on`, adicionado na 29.8/débito S4). É o
# ponto único de leitura da feature flag `FREQUENCIA_AUTORIZACAO_CASCATA`
# (Decisão D3 do CTO, 2026-10-02), consumido pela `Ability` (29.7) e pelos
# controllers de frequência, para que a chave da flag e o formato do log
# tenham UMA definição só.
#
# ── Decisão D3 (CTO) — três estados, default OFF ────────────────────────────
# A variável de ambiente `FREQUENCIA_AUTORIZACAO_CASCATA` aceita:
#   - ausente/vazia/qualquer outro valor → `:off`    (comportamento ATUAL — a
#     suíte existente e as telas NÃO mudam; é o default em produção);
#   - "shadow"/"sombra"                 → `:shadow` (só LOGA as negações que a
#     cascata faria, SEM negar — roda 1 ciclo antes de ligar de verdade);
#   - "on"/"1"/"true"/"ligada"          → `:on`     (a cascata passa a valer:
#     a `Ability` restringe a leitura de frequência e os index filtram por
#     `frequentadores_visiveis`).
#
# O valor é lido a cada chamada (não memoizado no carregamento): assim a flag
# pode ser trocada em runtime e os testes podem exercitar os três estados sem
# reiniciar o processo.
class FrequenciaAutorizacaoCascata
  VARIAVEL = "FREQUENCIA_AUTORIZACAO_CASCATA".freeze

  # Valores textuais aceitos para ligar a cascata de verdade.
  VALORES_LIGADA = %w[on 1 true ligada].freeze
  # Valores textuais aceitos para o modo shadow (só log).
  VALORES_SHADOW = %w[shadow sombra].freeze

  # Nome do evento de auditoria das negações PROJETADAS (shadow) — a decisão
  # que a cascata TOMARIA, sem negar. Único por conceito: o shadow e o `:on`
  # têm eventos distintos de propósito, para que a comparação (quantas seriam
  # negadas × quantas foram de fato) não precise de heurística sobre o payload.
  EVENTO_SHADOW = "frequencia_autorizacao_cascata.shadow".freeze
  # Tarefa 29.8 (débito S4 da 29.7) — evento de auditoria da negação EFETIVA,
  # emitido pelo modo `:on` (o único que nega). Mesmo payload do shadow
  # (`usuario, alvo, motivo, decisão`), para que os dois modos sejam
  # comparáveis linha a linha: a diferença entre "shadow" e "on" fica só no
  # NOME do evento, nunca no formato.
  EVENTO_NEGACAO = "frequencia_autorizacao_cascata.negacao".freeze

  class << self
    # `:off` | `:shadow` | `:on` — ver bloco de decisão no topo.
    def modo
      case ENV[VARIAVEL].to_s.strip.downcase
      when *VALORES_LIGADA then :on
      when *VALORES_SHADOW then :shadow
      else :off
      end
    end

    # Cascata valendo de verdade (restringe acesso/listagem).
    def ligada?
      modo == :on
    end

    # Cascata apenas observando (loga negações sem negar).
    def shadow?
      modo == :shadow
    end

    # Modo shadow: registra a decisão que a cascata TOMARIA, por alvo — sem
    # negar nada. Formato pedido pelo critério da 29.7:
    # `usuario, alvo, motivo, decisão`. O `motivo` é o do PORO (`:negado` ou um
    # dos passos 1–5), e a `decisao` é o veredicto projetado (`:negaria` /
    # `:permitiria`).
    #
    # Nível `info` (não `warn`): é observação de rollout, não uma negação
    # efetiva — a negação real (quando a flag estiver `:on`) virá do
    # `CanCan::AccessDenied`/filtro, não daqui.
    def log_shadow(usuario:, alvo:, motivo:, decisao:)
      return unless shadow?

      emitir(EVENTO_SHADOW, usuario:, alvo:, motivo:, decisao:)
    end

    # Tarefa 29.8 (débito S4 da 29.7) — registra a negação EFETIVA do modo
    # `:on` (o único que nega de verdade). Mesmo payload do shadow e mesma
    # normalização, mudando só o evento — é o que torna os dois modos
    # comparáveis: `EVENTO_SHADOW` diz o que SERIA negado; `EVENTO_NEGACAO`, o
    # que FOI. Sem esto, auditar uma produção com a flag ligada não deixa
    # rastro de quem foi barrado (o `CanCan::AccessDenied` só redireciona).
    #
    # Nível `info` KEPT idêntico ao shadow de propósito: os dois fluxos devem
    # ser comparáveis pela mesma consulta de log. `decisao` continua `:negaria`
    # por contrato do emissor, embora no `:on` o veredicto seja efetivo.
    def log_negacao(usuario:, alvo:, motivo:, decisao: :negaria)
      return unless ligada?

      emitir(EVENTO_NEGACAO, usuario:, alvo:, motivo:, decisao:)
    end

    private

    # Formatação ÚNICA do payload de auditoria (shadow e `:on`). Centralizar
    # aqui garante que os dois eventos não divirjam em campos/normalização —
    # a comparabilidade entre shadow e on depende disso.
    def emitir(evento, usuario:, alvo:, motivo:, decisao:)
      Rails.logger.info(
        evento: evento,
        usuario_id: usuario&.id,
        alvo_tipo: alvo.class.name,
        alvo_id: alvo&.id,
        alvo_cpf: normalizar_cpf(alvo&.cpf),
        motivo: motivo,
        decisao: decisao
      )
    end

    # CPF sem máscara — mesmo formato dos demais pontos de leitura de CPF do
    # domínio (`AutorizacaoFrequencia`/`User`).
    def normalizar_cpf(valor)
      valor.to_s.gsub(/\D/, "").presence
    end
  end
end
