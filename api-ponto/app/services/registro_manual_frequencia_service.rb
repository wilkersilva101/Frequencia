# Sprint 19, task 19.1 (UC-08) — orquestra a criação de uma
# IntervencaoFrequencia, portado de `RegistroFrequencia#manualFromForm`
# (intranet/src/modules/presenca/beans/RegistroFrequencia.java:214-246).
#
# Batida manual (tipo: "batida_manual"): cria o TimeRecord real na hora
# (authentication_mode: "manual") e a IntervencaoFrequencia com
# status: "registrado", igual ao legado faz `Dao.save(this)` ANTES de criar
# a intervenção quando `!errata`.
#
# Errata (tipo: "errata"): NÃO cria TimeRecord — só a IntervencaoFrequencia
# com status: "pendente", igual ao legado só roda `Dao.save` no branch
# `!errata`. A resolução (aprovar cria o TimeRecord; rejeitar mantém só o
# histórico) é escopo de task futura da Sprint 19 (provavelmente 19.2,
# "desconsiderar/reconsiderar ponto") — não implementada aqui.
class RegistroManualFrequenciaService
  class << self
    # @param user [User] frequentador afetado
    # @param responsavel [User] admin que está registrando/solicitando
    # @param tipo ["batida_manual", "errata"]
    # @param momento [Time] data/hora do registro sendo inserido/corrigido
    # @param punch_type ["entry", "exit", nil]
    # @param justificativa [String] obrigatória
    # @return [IntervencaoFrequencia]
    def registrar(user:, responsavel:, tipo:, momento:, punch_type: nil, justificativa:)
      ApplicationRecord.transaction do
        time_record = nil

        if tipo == "batida_manual"
          time_record = TimeRecord.create!(
            user: user,
            punched_at: momento,
            punch_type: punch_type,
            authentication_mode: "manual",
            raw_data: "Batida manual registrada por #{responsavel.nome_completo}"
          )
        end

        IntervencaoFrequencia.create!(
          user: user,
          responsavel: responsavel,
          tipo: tipo,
          justificativa: justificativa,
          momento: momento,
          punch_type: punch_type,
          time_record: time_record,
          status: tipo == "batida_manual" ? "registrado" : "pendente"
        )
      end
    end
  end
end
