# 29.2-D7 (decisão do CTO, 2026-09-29) — invariante de auto-gerência em UM só
# lugar.
#
# O invariante canônico é: **nenhum vínculo ATIVO liga o gestor a si mesmo**.
# Vínculo inativo de auto-gerência é histórico (não é auto-autorização
# corrente) e pode ser reescrito — é o dado legado que a importação da 29.3
# precisa reconciliar.
#
# Por que este módulo existe: a regra cruzava duas tabelas
# (`gestores_individuais.gestor_user_id` × `gestor_individual_gerenciados.user_id`)
# e por isso não cabe num `CHECK` do Postgres — tinha de ser validada nos dois
# models. Estava **copiada** em `GestorIndividual` e em
# `GestorIndividualGerenciado`, e essa duplicação produziu, em três rodadas
# seguidas de Bug Finder, a mesma classe de bug em eixos diferentes (o achado
# repetido foi sempre *assimetria entre validação-de-model e constraint-de-banco*):
#
#   - Bug 12 (r2): só um lado ganhou o filtro `if: :ativo?` da validação de par;
#   - Bug 17 (r3): a validação do gestor rodava em todo save e **algemava** o
#     registro (não editava, não desativava, sem saída in-app);
#   - Bug 18 (r3): os dois lados **discordavam** sobre o mesmo vínculo inativo.
#
# Centralizar a regra elimina a possibilidade de corrigir um lado e esquecer o
# outro — que foi exatamente a causa-raiz dos três.
#
# Como cada model participa (a assimetria de "de quem é o evento" é
# deliberada, não acidente):
#
#   - `GestorIndividual` (host): o evento que muda o invariante é
#     **definir/alterar o login** (`gestor_user_id`). Por isso o gatilho é
#     event-scoped (`new_record? || will_save_change_to_gestor_user_id?`):
#     renomear um gestor não cria nem desfaz auto-gerência e **não** deve
#     revalidar — senão um registro já inconsistente fica travado (Bug 17).
#   - `GestorIndividualGerenciado` (host): o evento é o **save do vínculo**,
#     que já é por natureza "o vínculo mudou"; o filtro aqui é `if: :ativo?`,
#     espelhando o índice UNIQUE parcial do banco (Bug 12/Bug 18).
#
# Ou seja, o módulo centraliza **a regra e os dois lados da matriz**; cada host
# declara *quando* revalidar. Testado nos 4 quadrantes de `ativo`
# (ativo/ativo, ativo/inativo, inativo/ativo, inativo/inativo) pelos dois lados
# e pelo banco — item permanente do `structural-conformity-checklist` (decisão
# (d) do CTO).
module InvarianteAutoGerencia
  extend ActiveSupport::Concern

  # O módulo NÃO registra o `validate` sozinho: cada host declara o SEU gatilho,
  # porque o evento que muda o invariante é diferente em cada um (login do
  # gestor vs. save do vínculo). O que fica centralizado aqui é a **regra** —
  # impossível de corrigir num lado e esquecer no outro.
  #
  # Achado 5/6 do Code Reviewer (2026-09-29) — o `include` NÃO pode ser no-op.
  # A primeira versão deste módulo só expunha o método de validação e deixava
  # cada host registrar o `validate` com o SEU `if:`. O reviewer mostrou que
  # isso reproduzia exatamente o eixo que já mordeu 3 vezes: o **gatilho**
  # (a assimetria de "quando revalidar") continuava duplicado e livre para ser
  # mudado num host só. Agora o módulo é dono do wiring: ele registra o
  # `validate` no `included do` e chama `janela_de_revalidacao`, que cada host
  # define. Mudar o gatilho num host só deixa de ser possível.
  included do
    validate :auto_gerencia_nao_ativa, if: :janela_de_revalidacao
  end

  private

  # Nome único (prefixado pelo módulo) para os dois hosts: evita colisão com
  # `validate`/métodos do próprio model e deixa claro na stack de onde vem.
  def auto_gerencia_nao_ativa
    return unless host_tem_auto_gerencia_ativa?

    errors.add(host_erro_attribute, host_erro_mensagem)
  end

  # --- Ponto de extensão: cada host responde pelos SEUS dados ---------------
  # (implementação padrão = lado do VÍNCULO, que tem as duas colunas na mesma
  # linha; o lado do GESTOR sobrescreve os três métodos abaixo.)

  # Há vínculo ATIVO ligando este gestor a si mesmo?
  #
  # Há DOIS defeitos opostos possíveis neste ponto, e a solução tem de cobrir
  # os dois — cada um foi um bug real nas rodadas de Bug Finder:
  #
  #   (a) Instância **stale** (achado 1 do Code Reviewer, 🟠): o gestor foi
  #       carregado antes de ganhar `gestor_user` em OUTRA instância; ler só a
  #       memória deixava a auto-gerência passar.
  #   (b) `reload` da instância recebida (Bug 1 do Bug Finder da D7, 🟠): a
  #       primeira tentativa de corrigir (a) fazia `gestor.reload` aqui. Isso
  #       **muta o objeto do chamador** e **descarta mudanças pendentes** — no
  #       caminho normal da 29.3 (carrega o gestor → resolve o login → grava o
  #       vínculo, sem salvar o gestor antes) o `reload` apagava o
  #       `gestor_user` recém-atribuído e o código **gravava auto-gerência
  #       ATIVA**. Trocava um falso-positivo por um falso-negativo pior.
  #
  # A leitura correta é **somar os dois lados sem mutar nada**: o valor em
  # memória (cobre o login pendente do chamador) **e** o valor no banco (cobre
  # o login já salvo por outra instância), consultado com `where(...).pick`, que
  # NÃO toca no objeto recebido. Um `SELECT` por validação; sem `reload`.
  def host_tem_auto_gerencia_ativa?
    return false if user_id.blank?

    gestor = gestor_individual
    return false if gestor.nil?

    logins = [ gestor.gestor_user_id ]
    if gestor.persisted?
      # `pick` devolve o valor do banco sem instanciar nem recarregar nada.
      logins << GestorIndividual.where(id: gestor.id).pick(:gestor_user_id)
    end

    ativo? && logins.compact.include?(user_id)
  end

  def host_erro_attribute
    :user_id
  end

  # Achado 14 do Code Reviewer — mensagens de invariante passam por I18n (a
  # task que introduziu o módulo também mexeu no `pt-BR.yml` por completude de
  # i18n; deixar hardcoded seria exceção não documentada).
  def host_erro_mensagem
    I18n.t("activerecord.errors.models.gestor_individual_gerenciado.auto_gerencia")
  end
end
