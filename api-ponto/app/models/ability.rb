# Sprint 23, task 23.5 — Ability (CanCanCan).
# Atualizado na task 23.7: baseline de leitura para autenticados (ver
# DECISÃO — transição abaixo).
#
# Mapeia as permissões do Frequencia por role Rolify (admin/gestor/operador),
# de forma que os controllers possam autorizar ações com `can?`/`cannot?`
# (integração real nos controllers feita na task 23.7 — esta task criou o
# model e a 23.7 integra nos controllers com `check_authorization`,
# `rescue_from` e `authorize!`).
#
# DECISÃO — convivência `admin?` (coluna booleana) × roles Rolify:
# durante a transição, um usuário é considerado admin se ELE É admin pela
# coluna booleana legada OU pela role Rolify (`user.admin? || user.has_role?(:admin)`).
# Esta dupla fonte de verdade é proposital: garante que contas legacy
# (coluna `admin = true`) continuem autorizadas mesmo sem a role, e que
# contas novas com a role admin funcionem antes da migração da coluna.
#
# DECISÃO — turn 23.7 (baseline de leitura para autenticados):
# a task 23.7 impõe "capacidade de acesso atual não pode diminuir". ANTES
# do CanCanCan nos controllers, QUALQUER usuário logado (mesmo sem role)
# acessava as telas read-only (Dashboard, TimeRecords, Frequencia, listagens
# de Estacoes/Versoes/Regimes etc.) por exigir apenas `require_login`.
# Para não quebrar essa capacidade na transição, todo usuário autenticado
# (com `id`) recebe `can :read, :all` como baseline — SEM permissão de
# escrita. Roles adicionais concedem permissões extras (gestor gerencia
# TimeRecord/IntervencaoFrequencia; admin gerencia tudo). Guest (User novo,
# sem id) continua sem NENHUMA permissão.
#
# Matriz de permissões:
#   - guest  → NENHUMA permissão (early return).
#   - autenticado sem role → `can :read, :all` (baseline de transição —
#     preserva o acesso read-only que existia antes de 23.7).
#   - :admin   → `can :manage, :all` (acesso total).
#   - :gestor  → `can :read, :all` (baseline) + `can :manage` em
#                `TimeRecord` e `IntervencaoFrequencia` — o gestor consulta
#                todas as telas e GERENCIA registros de ponto e intervenções
#                (batida manual, errata, desconsideração/reconsideração,
#                horas extras, prédio). Escopo por frequentadores gerenciados
#                (`GestorIndividualGerenciado`) NÃO foi implementado (evolução
#                futura documentada na iteration 23).
#   - :operador → `can :read, :all` — somente telas de consulta.
#
# Models `Pessoas::*` (espelho readonly do Pessoas2): `can :read, :all`
# cobre a leitura deles por design — são projeções somente-leitura
# (`PessoasRecord#readonly?`), então conceder leitura não cria risco de
# escrita; os arquivos em `app/models/pessoas/` NÃO são tocados.
#
# DECISÃO — Tarefa 29.7 (cascata de autorização de frequência, atrás de flag):
# ver `FrequenciaAutorizacaoCascata` (Decisão D3 do CTO, 2026-10-02) e a
# §Decisão D2 do `iteration_29.md`. Com a flag `FREQUENCIA_AUTORIZACAO_CASCATA`
# LIGADA (`:on`), o baseline `can :read, :all` deixa de cobrir os RECURSOS DE
# FREQUÊNCIA — `TimeRecord`, `CalculoDiario`, `RegistroMensalFrequencia`,
# `IntervencaoFrequencia` — que passam a ser liberados segundo a cascata das
# 29.4/29.6 (`pode_ver?` por alvo; conjunto de visíveis por CPF para leitura de
# classe). As DEMAIS telas/seções mantêm `can :read, :all` (D2: remover SÓ para
# frequência). Com a flag DESLIGADA (`:off`, default em produção) ou em shadow,
# o comportamento é EXATAMENTE o atual: o `can :read, :all` segue intacto e a
# suíte existente não regride.
#
# ⚠️ Limite medido (CanCanCan 3.6.1): `accessible_by` NÃO aceita regra com
# bloco (`block 'can' definition` → `CanCan::Error`). Por isso as regras por
# bloco abaixo servem a `can?`/`authorize!` por INSTÂNCIA; a listagem SQL
# (`accessible_by`/index) é responsabilidade dos controllers, que filtram por
# `Pessoas::Vinculo.cpfs_frequentadores_visiveis`. O bloco devolve `true` para
# `can?(:read, TimeRecord)` (chamada por CLASSE, feita por `load_and_authorize_
# resource` e por views): quem chegou até aqui já é autenticado (guard acima) e
# a restrição fina de "quais registros" é aplicada na listagem — o bloco de
# fatia por instância não pode ser avaliado sem uma instância.
class Ability
  include CanCan::Ability

  # Recursos de frequência afetados pela D2 (subtraídos do baseline `:all`
  # quando a cascata está ligada). Ordem = mesma do critério da 29.7.
  RECURSOS_FREQUENCIA = [
    TimeRecord,
    CalculoDiario,
    RegistroMensalFrequencia,
    IntervencaoFrequencia
  ].freeze

  def initialize(user)
    user ||= User.new

    # Guest (user não persistido) não recebe nenhuma permissão.
    return unless user.id

    # Task 23.7 — baseline de transição: todo autenticado mantém o acesso
    # de leitura que já tinha antes do CanCanCan (não diminui capacidade).
    # Task 29.7 (D2): quando a cascata está ligada, o `:all` NÃO cobre os
    # recursos de frequência — ver `deny_frequencia_baseline!` abaixo.
    can :read, :all
    deny_frequencia_baseline! if FrequenciaAutorizacaoCascata.ligada?

    if admin?(user)
      can :manage, :all
      return
    end

    grant_leitura_frequencia(user) if FrequenciaAutorizacaoCascata.ligada?

    return unless user.has_role?(:gestor)

    grant_gestao_frequencia(user)
  end

  private

  # Task 23.5 — fonte de verdade dupla durante a transição coluna
  # booleana `admin` × role Rolify `:admin` (ver DECISÃO no topo do arquivo).
  def admin?(user)
    user.admin? || user.has_role?(:admin)
  end

  # Task 29.7 (D2) — remove a leitura de frequência do baseline `can :read,
  # :all` (que é uma regra de `:all` e não pode ser "fatiada" por classe). O
  # `cannot :read, RECURSO` é uma regra de CLASSE com precedência sobre o `:all`
  # (mesma ordenação do probe), de modo que `can?(:read, TimeRecord)` por classe
  # passa a exigir a regra explícita de frequência concedida abaixo. As demais
  # seções (Dashboard, Users, Estações, Regimes, Presença...) seguem cobertas
  # pelo `:all`.
  #
  # Ordem importa e mantém o admin intacto: `deny_frequencia_baseline!` roda
  # ANTES do curto-circuito `can :manage, :all` do admin, e `manage` inclui
  # `read` no CanCan — então o admin continua lendo frequência. O `gestor`
  # recebe, adiante, as regras de frequência explícitas (por bloco).
  def deny_frequencia_baseline!
    RECURSOS_FREQUENCIA.each { |recurso| cannot :read, recurso }
  end

  # Task 29.7 — leitura de frequência pela cascata (flag ligada). Cada recurso
  # de frequência é liberado por INSTÂNCIA conforme o alvo (`user_id` do
  # registro) pertencer ao conjunto visível do usuário logado. A regra por
  # bloco NÃO alimenta `accessible_by` (limite medido) — a listagem é filtrada
  # no controller.
  #
  # `admin?` já retornou antes (`can :manage, :all`), então este caminho nunca
  # é alcançado por admin; ainda assim a guarda `admin?` é mantida defensiva.
  def grant_leitura_frequencia(user)
    can :read, TimeRecord do |registro|
      visivel_user_id?(user, registro.respond_to?(:user_id) ? registro.user_id : registro.user&.id)
    end

    can :read, CalculoDiario do |registro|
      visivel_user_id?(user, registro.respond_to?(:user_id) ? registro.user_id : registro.user&.id)
    end

    can :read, RegistroMensalFrequencia do |registro|
      visivel_user_id?(user, registro.respond_to?(:user_id) ? registro.user_id : registro.user&.id)
    end

    can :read, IntervencaoFrequencia do |intervencao|
      dono = intervencao.respond_to?(:user_id) ? intervencao.user_id : intervencao.user&.id
      visivel_user_id?(user, dono)
    end
  end

  # Task 29.7 — `gestor` gerencia SOMENTE frequência de frequentadores
  # visíveis (D2/critério: `can :manage` de `TimeRecord`/`IntervencaoFrequencia`
  # restrito ao escopo). Com a flag DESLIGADA mantém-se o comportamento atual
  # (manage sem escopo — suíte 23.x sem regressão).
  def grant_gestao_frequencia(user)
    if FrequenciaAutorizacaoCascata.ligada?
      can [ :create, :update, :destroy ], TimeRecord do |registro|
        visivel_user_id?(user, registro.respond_to?(:user_id) ? registro.user_id : registro.user&.id)
      end

      can [ :create, :update, :destroy, :deferir, :indeferir ], IntervencaoFrequencia do |intervencao|
        dono = intervencao.respond_to?(:user_id) ? intervencao.user_id : intervencao.user&.id
        visivel_user_id?(user, dono)
      end
    else
      can :manage, TimeRecord
      can :manage, IntervencaoFrequencia
    end
  end

  # O `user_id` do registro está entre os CPFs dos frequentadores visíveis do
  # usuário. A ponte é o CPF (`users.cpf` ↔ `Pessoas::Vinculo`), porque
  # `time_records.user_id` aponta para `users` locais. A chave estrangeira
  # `user_id` é imutável na prática (um `TimeRecord`/`CalculoDiario` pertence a
  # um dono), então o memo por `user_id` é seguro.
  #
  # `admin?` curto-circuita (defensivo — admin já retornou). Fail-closed:
  # alvo nulo/CPF ausente → oculto.
  def visivel_user_id?(user, user_id)
    return true if admin?(user)
    return false if user_id.blank?

    ids = (@visiveis_user_ids ||=
      User.where(cpf: Pessoas::Vinculo.cpfs_frequentadores_visiveis(user)).pluck(:id))
    ids.include?(user_id)
  end
end
