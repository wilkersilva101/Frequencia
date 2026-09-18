module Presenca
  class ValidarFrequentadorController < ApiController
    def show
      # Sprint 1 (Task 1.4): antes validava contra uma whitelist hardcoded de
      # códigos de ativação; agora valida contra estações reais cadastradas
      # em `EstacaoPonto` (mesma resposta/formato do protocolo, apenas a
      # fonte do dado mudou — ver ADR-0003).
      unless EstacaoPonto.codigo_ativacao_valido?(params[:codAtivacao])
        return render plain: "USUARIO_SENHA_INVALIDOS"
      end

      username = CryptoDes.decrypt(params[:loginAccessKey].to_s)
      password = CryptoDes.decrypt(params[:plainPassword].to_s)

      user = User.ativos.find_by(username: username)

      if user&.authenticate(password)
        render plain: user.id.to_s
      else
        render plain: "USUARIO_SENHA_INVALIDOS"
      end
    rescue
      render plain: "USUARIO_SENHA_INVALIDOS"
    end
  end
end