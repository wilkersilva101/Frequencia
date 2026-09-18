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
class Ability
  include CanCan::Ability

  def initialize(user)
    user ||= User.new

    # Guest (user não persistido) não recebe nenhuma permissão.
    return unless user.id

    # Task 23.7 — baseline de transição: todo autenticado mantém o acesso
    # de leitura que já tinha antes do CanCanCan (não diminui capacidade).
    can :read, :all

    if admin?(user)
      can :manage, :all
      return
    end

    return unless user.has_role?(:gestor)

    can :manage, TimeRecord
    can :manage, IntervencaoFrequencia
  end

  private

  # Task 23.5 — fonte de verdade dupla durante a transição coluna
  # booleana `admin` × role Rolify `:admin` (ver DECISÃO no topo do arquivo).
  def admin?(user)
    user.admin? || user.has_role?(:admin)
  end
end
