# _context.md — progress
> Gerado em: 2026-10-05 | Fontes: iteration_29.md, quality/review_report_29_4..29_8.md, adr/0006-0008, iteration_chore_*.md, iteration_23/24/26.md | Palavras: ~720
> Atualizar quando: nova iteration criada; status de tarefa alterado; sprint concluída; push/MR; baseline da suíte remedido.

## O que esta pasta contém
Acompanha as sprints do Frequência, com um `iteration_N.md` por sprint. Sprints 23/24 encerradas; 26 consolidada; **29 é a sprint ativa e está COMPLETA** (29.0 a 29.8 entregues, aprovadas e commitadas). As chores transversais têm arquivo próprio (`iteration_chore_*.md`).

## Pontos-chave para agentes
### iteration_29.md — Sprint 29 (cascata de autorização de frequência) ✅ CONCLUÍDA
- **Entrega:** substitui o baseline "todo autenticado lê tudo" (23.7) pela cascata do legado — PORO `AutorizacaoFrequencia`/29.4 (5 passos + `motivo`, fail-closed), scope SQL `FrequentadoresVisiveis`/29.6 (equivalente item a item, sem N+1), PORO `ElegibilidadeDesconsideracao`/29.5 (gate **só do passo 5** — D5), integração na `Ability` + 6 controllers/29.7 e matriz/auditoria/29.8.
- **Flag `FREQUENCIA_AUTORIZACAO_CASCATA`** (`:off`/`:shadow`/`:on`, default **OFF**): `:on` restringe e loga negações; `:shadow` só loga; `:off` = comportamento idêntico ao atual. Preserva a visão global (admin / `visualiza_frequentadores`).
- **Rulings do CTO:** D1 (roles `visualiza_frequentadores`/`visualiza_terceirizados` — a de terceirizados só é significativa combinada); D4 (TERCEIRIZADO = `Vinculo#tipo_vinculo.nome == "Terceirizado"`); D5 (desconsiderar = **apenas** hierarquia/passo 5; `GestorIndividual` vê mas não desconsidera); D6 (unidade inelegível não libera, ausente não interrompe, path corrompido fail-closed); D8 (nunca `valid?` no caminho de leitura). ADR-0008 = semântica de `ativo` do gestor (**projeção**: `true` sse ≥1 vínculo ativo).
- **Débitos abertos:** 🟡 **S2** (twin SQL `geridos_user_ids` × PORO passo 4/GI inativo — a matriz é cega ao PORO; mutar `.ativos` do PORO não derruba teste de listagem) e 🟡 **S3** (`frequencia_por_orgao` fora do grão da matriz). Ambos com dono Sprint 30/chore e gatilho binário.

### iteration_chore_*.md
- **Stubs destrutivos** (`auditoria_stubs_destrutivos`): causa-raiz do 13º erro — `remove_method` do scope real `Pessoas::Vinculo.ativos` em `dashboard_controller_test.rb` vazava por processo; corrigido em `eb38b1e`; auditoria achou **8 arquivos vazando** (`43b7d84`); blindagens locais removidas (`166f51d`). Padronização de helper e cop anti-`remove_method` ficaram agendados (gatilho = tocar os arquivos).
- **`debitos_pre_29_7`**: 3 débitos fechados em `16c1c9a`.
- **`gitlab-ci`**: monorepo (raiz git = `Frequencia/`, app em `api-ponto/`) exige `.gitlab-ci.yml` na **raiz**; pipeline criado mas **bloqueado por infra — nenhum runner online**, o job `test` nunca rodou em runner real. **Não declarar concluída.**
- **`github-workflows`** e **`stub_nao_destrutivo`**: chores correlatas de esteira/teste.

### iteration_23.md / 24.md / 26.md
- 23: Devise + CanCanCan + Rolify (origem do baseline `can :read, :all`). 24: basic8. 26: 26.1–26.10 no commit `1a73a4d`.

## Estado atual
- Branch `integration/sprint-29` @ **`e795df9`**, **publicada no GitLab**. Sprint 29 fechada; sem pendência de commit.
- Commits da sprint: `0f1fdfd` (29.4), `29f719c` (29.6), `2b8e47a` (29.5), `16c1c9a` (débitos pré-29.7), `df57cf5` (29.7), `e795df9` (29.8); stubs `eb38b1e`/`43b7d84`/`166f51d`.
- **Baseline da suíte: 1083 runs / 3789 assertions / 1 failure + 11 errors / 0 skip.** As 12 são pré-existentes: 11× Devise `redirect_to` (`Users::SessionsControllerTest`/`PasswordsControllerTest`) + 1× timezone em `PresencaEndpointsTest`. Espelho Pessoas: 19/68/0/0.
- Próximo: **Sprint 30** (cascata/roles granulares + débitos S2/S3). Merge da 23.7 antes avaliado segue como débito.
- Dívidas de CI com dono/gatilho binário: bump Rails ≥8.1.x (`chore/bump-rails-8.1`, gatilho brakeman EXIT=0); 77 offenses RuboCop (`chore/limpeza-rubocop-77`, gatilho rubocop EXIT=0). Ambiente medido: Ruby **3.3.8** / Rails **8.0.5** → ver `governance/_context.md`.

## Referências para aprofundamento
- Estado/tarefas 29.0–29.8, rulings do CTO e baseline canônico → `docs/progress/iteration_29.md`
- Reviews 29.4/29.5/29.6/29.7/29.8 → `docs/quality/review_report_29_4.md` · `29_5` · `29_6` · `29_7` · `29_8`
- Bloco de esteira/CI → `docs/progress/iteration_chore_gitlab-ci.md`
- Stubs destrutivos → `docs/progress/iteration_chore_auditoria_stubs_destrutivos.md`
- ADRs 0006/0007/0008 → `docs/adr/0006-schema-teste-espelho-pessoas.md` · `0007-soft-delete-gestor-individual-e-politica-delecao-usuario.md` · `0008-semantica-estado-gestor-individual-e-identidade-legado.md`
- Regras e lições → `docs/governance/_context.md` e `docs/governance/lessons.md`
