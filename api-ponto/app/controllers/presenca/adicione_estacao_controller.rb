module Presenca
  class AdicioneEstacaoController < ApiController
    # Sprint 1 (Task 1.4): EP-06 (heartbeat) — antes um stub que sempre
    # respondia "OK" sem ler parâmetros nem persistir nada. Agora implementa
    # o contrato real documentado em `docs/07-estacao-ponto/02-endpoints-
    # consumidos.md` (EP-06): recebe `codAtivacao`, `versao` e
    # `estadoEstacao`, e responde "true"/"false" (string pura, não JSON) —
    # o mesmo formato que a EstaçãoPonto desktop já espera, apenas passa a
    # ser respondido com dado real em vez de um valor fixo (ADR-0003: sem
    # mudança de protocolo, apenas troca da fonte de dado).
    def show
      estacao = EstacaoPonto.registrar_contato(params[:codAtivacao], versao: params[:versao])

      render plain: estacao ? "true" : "false"
    end
  end
end
