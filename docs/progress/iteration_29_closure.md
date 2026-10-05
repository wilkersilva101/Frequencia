# Registro de fechamento — Sprint 29 (cascata de autorização de frequência)

> **Autor:** CTO (doc-only) · **Data:** 2026-10-05
> **Branch:** `integration/sprint-29` @ **`e795df9`** (publicada no GitLab).
> **Status:** ✅ **CONCLUÍDA** — 29.0–29.8 todas implementadas, aprovadas e commitadas.
> **Rastreabilidade canônica:** `docs/progress/iteration_29.md` (212 KB, registro primário de
> decisões, reviews e telemetria). **Este arquivo é o catálogo de fechamento** — visão consolidada
> para agentes e para a governança; não duplica o detalhe das tasks.

---

## 1. O que a Sprint 29 entregou

Substituiu o baseline "todo autenticado lê tudo" (Sprint 23.7) no domínio de frequência por uma
**cascata de autorização** — porte fiel do legado (`RegistroFrequenciaValidator.frequentador`,
`RegistroFrequenciaServices.podeDesconsiderarFrequencia`) — com **rollout por feature flag** e
**dual-implementação** (PORO de consulta × scope SQL) atrás da mesma semântica.

| Task | Entrega | Artefato principal |
|------|---------|--------------------|
| 29.0 | Schema de teste do espelho Pessoas (ADR-0006) | `test/support/pessoas_schema.rb`, rake `test:pessoas_schema:load` |
| 29.1 | Exposição de hierarquia/gestores de órgão no espelho | `Pessoas::Unidade#gestor?/#cadeia_ascendente`, `Pessoas::Pessoa.por_user` |
| 29.2 | Schema de `GestorIndividual` para dado real (migração aditiva) | `gestores_individuais` + `gestor_individual_gerenciados` |
| 29.3 | Importação idempotente de gestores individuais do Intranet | `ImportarGestoresIndividuaisService`, Job, rake |
| **29.4** | **Cascata de visualização — PORO de consulta** | `app/models/autorizacao_frequencia.rb` |
| **29.5** | **Elegibilidade para desconsiderar um dia — PORO** | `app/models/elegibilidade_desconsideracao.rb` + `AutorizacaoFrequencia#gestor_de_orgao_do?` |
| **29.6** | **Scope de listagem — irmão SQL** | `app/models/frequentadores_visiveis.rb` + `Pessoas::Vinculo.frequentadores_visiveis` |
| **29.7** | **Integração na `Ability` e controllers (por bloco), atrás da flag** | `FrequenciaAutorizacaoCascata`, concern `FrequenciaAuthorization`, 6 controllers |
| **29.8** | **Matriz de aceite (12 cenários) + auditoria de negação no `:on`** | testes + mutation testing (14/14 mortas) |
| esteira | `bin/brakeman` sem `--ensure-latest`, ledger + flags anti-drift, banco espelho no CI | `.gitlab-ci.yml` (fork), `config/brakeman.ignore` |

**Semântica de autorização consolidada (grounded no legado):**
- **Passos da cascata de VISUALIZAÇÃO** (29.4/29.6, `pode_ver?`): `1` próprio · `2` admin OU
  `visualiza_frequentadores` (precedência, curto-circuito) · `3` `visualiza_terceirizados` E alvo
  Terceirizado · `4` `GestorIndividual` **ativo** · `5` **hierarquia** (gestor do órgão do alvo, via
  `cadeia_ascendente`). Sem nenhuma role e sem 1/4/5 → **`:negado`**.
- **D1** (roles `visualiza_frequentadores`/`visualiza_terceirizados`) e **D4** (TERCEIRIZADO = **tipo
  de vínculo** `Pessoas::TipoVinculo#nome == "Terceirizado"`, não categoria eSocial) — rulings do CTO de 2026-09-29.
- **D5** (ruling de 2026-10-01): o acionador de **desconsiderar um dia** é **apenas o passo 5**
  (hierarquia); `GestorIndividual` (passo 4) **vê mas não desconsidera**. O legado trata **ver** e
  **desconsiderar** como regras **distintas**.
- **D2**: a `Ability` subtrai o baseline `can :read, :all` **apenas** para recursos de frequência
  quando a flag está `:on`; demais telas permanecem.

### Feature flag — `FREQUENCIA_AUTORIZACAO_CASCATA` (`app/models/frequencia_autorizacao_cascata.rb`)

Ponto **único** de leitura da flag, lida **a cada chamada** (não memoizada — permite troca em runtime
e testes dos 3 estados sem reiniciar o processo):

| Valor de ENV | Modo | Efeito |
|--------------|------|--------|
| ausente/vazio/outro | **`:off`** | comportamento **atual**; default em produção |
| `shadow`/`sombra` | `:shadow` | **só LOGA** as negações que a cascata faria (`EVENTO_SHADOW`), **sem negar** — roda 1 ciclo antes de ligar |
| `on`/`1`/`true`/`ligada` | `:on` | cascata **vale**: `Ability` restringe + index filtram + log de negação **efetiva** (`EVENTO_NEGACAO`, débito S4/29.8) |

Payload de auditoria único (`usuario`, `alvo`, `motivo`, `decisao`) nos dois eventos — comparáveis
linha a linha (a diferença fica **só no nome do evento**).

### Débitos abertos (não-bloqueantes) herdados pelo fechamento

- 🟡 **S2 — twin SQL×PORO (blind spot do passo 4/GI inativo).** O `FrequentadoresVisiveis#geridos_user_ids`
  usa `.ativos`; o **gêmeo do PORO** (`AutorizacaoFrequencia#gestor_individual?`) tem a mesma construção,
  e o **mesmo bug passaria verde**: a matriz exercita o **scope SQL** (caminho de listagem), **não o PORO**
  (que só alimenta o `motivo` do log). Mutar o `.ativos` do PORO **não derruba** nenhum teste de listagem.
  **Dono:** Sprint 30 (cascata/roles granulares) ou chore de hardening do passo 4. **Gatilho binário:**
  existir um teste que exercite o **PORO** `AutorizacaoFrequencia#motivo` com GI **inativo** (assert
  `:negado`) **E** o twin SQL com o mesmo cenário, ambos no baseline. Enquanto não existir, o furo fica
  aberto por construção.
- 🟡 **S3 — `frequencia_por_orgao` fora do grão da matriz.** A matriz de aceite não cobre o grão desse
  controller com a mesma profundidade das demais telas. (O cenário 12 — **sem CPF** — está coberto e
  registra fail-closed: um não-admin sem CPF vê zero registros sob `:on`, perdendo os próprios; a decisão
  de produto sobre contas locais sem CPF é do **PO**.)

> **Achado de segurança novo (não é da cascata, mas toca o gate):** o warning `SQL Injection` Medium em
> `frequentadores_visiveis.rb:351` (nasceu na 29.7, commit `16c1c9a`) está **fora** do ledger Brakeman e
> impede o `EXIT 0`. Ver `docs/progress/iteration_chore_bump_rails_81.md` §5 e a ADR-0009 regra 5.

---

## 2. Algo merece virar ADR? — **sim: ADR-0010 (recomendado)**

**ADR-0009 está ocupada** (toolchain Ruby/Rails + política do ledger — ver
`docs/adr/0009-estrategia-versao-toolchain-ruby-rails.md`). O candidato natural da Sprint 29 é a
**ADR-0010 — Arquitetura da cascata de autorização de frequência**.

**Justifica-se** porque a Sprint produziu **decisões duráveis e não-óbvias** que outros agentes precisam
seguir e que hoje vivem apenas **dentro de um `iteration_29.md` de 212 KB** (difícil de descobrir/auditar):

1. **Dual-implementação canônica (PORO × SQL)** — a mesma semântica existe em dois lugares
   (`AutorizacaoFrequencia` para decisão/log; `FrequentadoresVisiveis` para listagem), **sem JOIN
   cross-database** (`users` primário × `pessoas/vinculos` espelho) ⇒ passos 1/4 em Ruby → `IN (cpfs)`,
   passos 3/5 em SQL. É um **contrato de arquitetura** com risco de **drift** (débito 🟡S2) — exatamente o
   tipo de coisa que uma ADR fixa com regra de conformidade.
2. **Feature flag de 3 estados com default OFF** e eventos de auditoria separados (shadow × negação).
3. **Distinção semântica "ver ≠ desconsiderar" (D5)** — regra **não-óbvia** e fail-closed, decidida a
   partir da fonte primária do legado.
4. **Regime de autorização pós-baseline (D1/D2)** — remoção cirúrgica do `can :read, :all` **só** para
   frequência, com curto-circuito de admin; e a consequência de **fail-closed** para contas sem CPF.
5. **Débitos com gatilho binário** (S2) — uma ADR dá o lugar certo para o gatilho de remoção da dívida.

> **Recomendação:** o CTO (próxima sessão) redigir a **ADR-0010** a partir dos rulings já registrados em
> `iteration_29.md` (§D1/D2/D5, §Ruling M2 e §Matriz 29.8). **Não** redigida nesta sessão para não
> duplicar conteúdo antes do fechamento formal; este catálogo é o gatilho.

---

## 3. Sinais de governança (para o coordenador / summarizer)

O CTO **não** regenera `_context.md` (papel do **summarizer**). Sinalo o que está **obsoleto**:

| Arquivo | Está stale em | Deveria dizer |
|---------|---------------|---------------|
| `docs/governance/_context.md` | "ADRs `0000`–`0007`" (corpo) | **`0000`–`0009`** (existe 0008 e agora 0009) |
| `docs/governance/_context.md` | "27 lições" | **36** lições (`grep -cE '^### [0-9]{4}-[0-9]{2}-[0-9]{2}' docs/governance/lessons.md`) |
| `docs/governance/_context.md` | Rails "8.0.5" / dívida aberta | **8.1.4** (após a chore) + dívida **fechada** pela ADR-0009 |
| `docs/progress/_context.md` | (em edição pelo **summarizer**) | — não tocar |
| `AGENTS.md` (raiz) | "Rails 8.0.4 / Ruby 4.0.0" | 3.3.8 / 8.1.4 (passo da chore) |

---

## 4. Checklist de fechamento

- [x] 29.0–29.8 implementadas, aprovadas (0 blockers) e commitadas
- [x] Flag `FREQUENCIA_AUTORIZACAO_CASCATA` com default **OFF** (3 estados)
- [x] Débitos 🟡S2 (twin SQL×PORO) e 🟡S3 (grão `frequencia_por_orgao`) com dono/gatilho
- [x] ADR-0009 (toolchain) registrada; **ADR-0010 (cascata) recomendada**
- [x] Este catálogo de fechamento criado
- [ ] (coordenador) acionar **summarizer** para `governance/_context.md`
- [ ] (chore) bump Rails 8.1.4 + correção das 3 fontes de versão → ver
      `docs/progress/iteration_chore_bump_rails_81.md`
