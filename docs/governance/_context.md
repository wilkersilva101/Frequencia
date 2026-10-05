# _context.md — governance
> Gerado em: 2026-09-30 | Fontes: docs/governance/lessons.md, docs/adr/ (0000–0008), AGENTS.md (raiz), docs/progress/iteration_chore_gitlab-ci.md | Palavras: ~520
> Atualizar quando: lição registrada em lessons.md; ADR nova; mudança nas regras/configurações do AGENTS.md (raiz); mudança do ambiente medido (Ruby/Rails).

## O que esta pasta contém
Diretrizes de governança do AI Workflow aplicadas ao Frequência. As regras canônicas vivem no `AGENTS.md` da raiz (lido por OpenCode/Antigravity); a pasta guarda o registro de **lições aprendidas** não cobertas por iteration/quality/ADRs (não há pasta `rules/` aqui — desvio de estrutura, ver `docs/_context.md`). Os ADRs vivem em `docs/adr/` (fora desta pasta, mas catalogados aqui).

## Pontos-chave para agentes
### lessons.md (27 lições — 2026-09-10 a 2026-09-30)
- **Ambiente real medido (2026-09-30):** Ruby **3.3.8** (`ruby -v`) e Rails **8.0.5** (`Gemfile.lock`); no Frequencia, preferir binstubs `bin/*` a `bundle exec` (`bundle exec rails` falha com `invalid switch in RUBYOPT`).
- Lições de auth (Sprint 23): Rolify `scopify` só cria scopes `global`/`class_scoped`/`instance_scoped`; rota custom Devise exige `devise_scope :user`; coexistência sessão legada × Warden exige `skip_before_action :verify_signed_out_user`. Timing side-channel: phantom work, nunca `sleep`.
- Lições da Sprint 29 (a maioria): `uniqueness` com `conditions:` valida o registro NOVO por inteiro e **não espelha índice UNIQUE parcial**; validação de invariante deve rodar **no evento** (`will_save_change_to_X?`), nunca em todo save (senão "algema" o registro); os **dois lados** de invariante cruzando tabelas devem concordar sobre os **4 quadrantes de `ativo`**; callback de validação **nunca** deve chamar `reload` na instância do chamador; `RecordInvalid#message` consulta `activerecord.errors.messages.record_invalid`.
- Lições de CI (chore do fork, 2026-09-29): gate vermelho em stage anterior impede o seguinte (fail-fast do GitLab); `localhost` **não** alcança `services:` no executor docker (resolvem por **alias**, sem forwarding de porta); config só de credentials quebra em CI limpo (sem `master.key`); código de saída com precedência interna pode **mascarar** a checagem que você ligou (Brakeman: exit 3 esconde 8/9).

### ADRs (`docs/adr/` — 0000 a 0008)
- 0001 integração Pessoas↔Frequência · 0002 estratégia de migração · 0003 compatibilidade EstaçãoPonto · 0004 spec-driven integração · 0005 destino PoC api-ponto · 0006 schema de teste do espelho Pessoas.
- **ADR-0007 (2026-09-29):** soft-delete do vínculo de gestão individual, invariante canônico de auto-gerência (*nenhum vínculo ATIVO liga o gestor a si mesmo*) e política de deleção de `User` (deleção é **soft**; FK `gestor_user_id` permanece `restrict`). Orienta 29.3/29.4/29.6.
- **ADR-0008 (2026-09-30):** semântica de `GestorIndividual#ativo` (projeção: ativo sse ≥1 vínculo ativo), determinismo por ordem, e reconciliação de identidade do legado (`id_vinculo` ≠ pessoa). Fecha as ressalvas (1)/(2) e o 🟡2 do review da 29.3; origem do complemento **29.3-D1..D4**.

### AGENTS.md (raiz — `/home/davi.queiroz/Área de trabalho/workspace_integração/AGENTS.md`)
- Identidade: sistema Frequência, Rails 8 API-only custom, Devise 5, CanCanCan 3.6, Rolify 6, Pagy 9, AdminLTE 4 + Bootstrap 5.3, importmap (sem Node).
- Configuração: TASK_MODE=STANDARD, COMMIT_MODE=manual, MEMORY_MODE=classic, SUGGESTION_LEVEL=1, BUG_LEVEL=1.
- ✅ **DOCS_PATH (dívida D4) — CORRIGIDA em 2026-09-30:** o `AGENTS.md` apontava para `workspace_integracao/docs/` (árvore paralela defasada, parada em 2026-09-21, **não versionada** — vive ACIMA da raiz git). Foi repontado para `Frequencia/docs/` (11 ocorrências) e a taxonomia da Seção 4 foi corrigida (layout numerado, não `inception/`/`analysis/`/`knowledge/`). **Processar sempre `Frequencia/docs/`.** A neutralização física da árvore morta (deletar/substituir por symlink) fica **proposta e pendente de aprovação do dev** (não apagar sem aprovação explícita). Resta avaliar migrar o `AGENTS.md` para dentro do repo (`Frequencia/AGENTS.md`, versionado) — hoje ele é não-versionado por viver acima da raiz git.

## Estado atual
- **27 lições registradas** (medido: `grep -cE "^### [0-9]{4}-[0-9]{2}-[0-9]{2}" docs/governance/lessons.md` = 27, todas distintas). **Reconciliação da contagem (D-doc):** o "23" era **stale** (correto em `6b91d37`); o review da 29.3 sugeriu "24" (correto em `109476e`); a chore de CI (`f82c965`) somou +1 (=25); a 29.3 (`a18f27c`) +1 (=26); e a lição da **29.3-casing** (CTO, 2026-09-30) +1 (=**27**). Todas com data e evidência de execução.
- **ADRs 0000–0008** (era "0001–0005" no snapshot anterior); o índice `docs/README.md` foi atualizado para `0000`–`0008`.
- **Dívida de versão do Ruby — DÍVIDA ABERTA (dono pendente):** três fontes conflitantes, **nenhuma** igual ao medido — `AGENTS.md` diz Ruby 4.0.0 / Rails 8.0.4; `.ruby-version`/`.tool-versions` dizem `ruby-4.0.0` (**não existe**); snapshot anterior deste arquivo dizia 3.4.2. **Medido 2026-09-30: Ruby 3.3.8 / Rails 8.0.5.** Não unificar por conta própria (blast radius da toolchain mise/asdf); há decisão de dono pendente.
- LIÇÕES deste ciclo (chore do fork): nenhuma lição do `iteration_chore_gitlab-ci.md` ficou pendente — as duas últimas (fail-fast + alias) já estão em `lessons.md`.

## Referências para aprofundamento
- Para lições aprendidas → `docs/governance/lessons.md`
- Para regras globais, pipeline e configurações → `/home/davi.queiroz/Área de trabalho/workspace_integração/AGENTS.md`
- Para decisões arquiteturais → `docs/adr/` (em especial `0007-soft-delete-gestor-individual-e-politica-delecao-usuario.md` e `0008-semantica-estado-gestor-individual-e-identidade-legado.md`)
- Para o ambiente real (versões medidas) → `docs/progress/iteration_chore_gitlab_ci.md` §Dívida registrada
- Para o padrão de índice parcial × validação → `docs/progress/iteration_29.md` (Riscos)
