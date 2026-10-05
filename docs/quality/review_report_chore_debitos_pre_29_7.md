# Review Report — chore `chore/debitos-pre-29-7` (débitos pré-29.7: D1, D2, D3)

> **Modo:** AGILE | **Revisor:** Code Reviewer | **Data:** 2026-10-02
> **Branch de origem:** `chore/debitos-pre-29-7` (worktree `wt-29x-debitos`) → **destino:** `integration/sprint-29`
> **Base:** `integration/sprint-29` @ `2b8e47a` | **COMMIT_MODE=manual** (revisor não commita)
> **Ambiente:** Ruby 3.3.8 / Rails 8.0.5 / PostgreSQL / minitest 6.0.6

## Escopo revisado

| Arquivo | Débito | Tipo |
|---|---|---|
| `api-ponto/app/models/elegibilidade_desconsideracao.rb` | D1 — contrato do PORO | produção |
| `api-ponto/app/models/frequentadores_visiveis.rb` | D2 — log agregado do scope | produção |
| `api-ponto/test/models/elegibilidade_desconsideracao_test.rb` | D1 | teste |
| `api-ponto/test/models/frequentadores_visiveis_test.rb` | D2 + D3 | teste |
| `docs/governance/lessons.md` | lição 3-valued logic | doc |
| `docs/progress/iteration_chore_debitos_pre_29_7.md` | rastreabilidade | doc |

Fora de escopo (trackeados, sujados pelos testes — **não** entram em commit): `api-ponto/log/test.log`, `api-ponto/tmp/cache/*`.

## Veredito

# ✅ APROVADO — com 1 sugestão de melhoria (🟡) e 1 débito de doc (🟠)

**Blockers (🔴): 0.** Nada impede o commit. As três correções são reais, os testes discriminam (reproduzido por mutação) e não há regressão.

---

## Resultado por débito

### D1 — Contrato estrito a `User` + fail-closed com log — ✅ CORRETO

- O guard (`unless frequentador.is_a?(User)`, `:93`) está **antes** de `Dia.para(frequentador, data)` (`:102`) — nenhuma chamada que quebraria é alcançada.
- **Mutação reproduzida:** desabilitei o guard → o teste D1 falha com o `NoMethodError` **exato** (`undefined method 'time_records' for an instance of Pessoas::Pessoa`, `dia.rb:45`). O teste exercita a mesma condição real.
- O teste positivo passa uma `Pessoas::Pessoa` **REAL** e assere `false` + log `elegibilidade_desconsideracao.alvo_nao_user`.
- **Controle positivo** (mesmo acionador/órgão, alvo `User` elegível) libera → o guard não é `return false` incondicional.
- **Controle do mascaramento:** acionador nulo + alvo não-`User` nega sem levantar (documentado).
- **Coerência com o alvo real da 29.7:** confirmada. O alvo vem do `TimeRecord` (FK `user_id` → `users`); incorreto seria o código, não o contrato. A decisão (a)+(b) é a certa.

### D2 — Log agregado no scope — ✅ CORRETO (com sobre-reporte defensável, ver 🟡1)

- **Equivalência intacta (reproduzida por probe):** `104 pares = 34 T / 70 F / 0 divergências` — idêntico ao número da 29.6.
- **Fidelidade no caso `sub_inativa` (reproduzida):** PORO loga 1× `unidade_inelegivel` com `unidade_id=17242`; o scope loga 1× o MESMO evento agregado (`unidade_ids=[17242]`). O `unidade_id` registrado é a unidade de **lotação do alvo** — o mesmo que o PORO registra.
- **N+1 (reproduzido):** o teste `D2: o log agregado nao introduz N+1` passa; contagem de queries constante.
- **Mutações reproduzidas:**
  - Remover `COALESCE` (`:338`) → falha **exatamente** o teste do agregado (`unidade_inelegivel`). Bug de 3-valued logic era **real**.
  - Remover a chamada `log_negacoes` (`:82`) → 2 failures (`pessoa_ausente` + `unidade_inelegivel`).
- **`NOT` reiterado:** varri o arquivo — o único `NOT (predicado)` propenso a NULL fora do `COALESCE` é o `cond` interno de `cadeia_tem_gestor` (`:366`), e ele é **consumido por dois `COALESCE`**: o fixado (`:338`, lado positivo) e o novo (`:340`, **este commit**, lado negativo). Está coberto. Os demais `NOT` (`:404`, `NOT (...) = ANY(...)`) operam sobre booleanos de valores não-nulos (`id`, `ancestry`), sem exposição.
- **Limites declarados honestos:** `ancestral_ausente` (4º log do PORO, em `Pessoas::Unidade#cadeia_ascendente`) fora do escopo nomeado; `pessoa_ausente` por ALVO não replicável sem N+1.

### D3 — Fixture multi-vínculo — ✅ CORRETO

- Asserção **por PESSOA** (união dos vínculos aprovados ⇔ pessoa aprovada), sob `visualiza_terceirizados` (passo 3).
- **Mutações reproduzidas:**
  - A (`role_terceirizados?` → `false`): o positivo **falha**.
  - C (`TIPO_TERCEIRIZADO = "Efetivo"`): o **controle negativo falha**.
  - A asserção discrimina — não é falso verde.

---

## Métricas (medidas independentemente)

| Métrica | Valor | Confere? |
|---|---|---|
| Arquivos-alvo juntos | **50 runs / 128 assertions / 0F / 0E / 0 skip** | ✅ |
| A/B serial multi-seed (seeds 1, 42) — alvos | 50/128/0F/0E em 2/2 | ✅ |
| Serial arquivos relacionados (`autorizacao_frequencia`, `ability`, `dia`, `time_record`, `calculo_diario`, `pessoas_pessoa`) — seeds 1/42/6000 | 95/266/0F/0E em 3/3 | ✅ |
| Equivalência propriedade | 104 pares = 34 T / 70 F / 0 div. | ✅ |
| Fidelidade `sub_inativa` (PORO × scope) | 1× evento, `unidade_id` idêntico (17242) | ✅ |
| Mutação D1 (guard off) | `NoMethodError` em `dia.rb:45` | ✅ |
| Mutação D2 (`COALESCE` off) | 1 failure (só agregado) | ✅ |
| Mutação D2 (`log_negacoes` off) | 2 failures | ✅ |
| Mutação D3 A / C | positivo / controle negativo falham | ✅ |
| Suíte completa | não re-executada (custo); baseline declarado 1036/3533/1F+11E/0skip | ⚠️ não reproduzido (ver Nota) |

**Nota sobre a suíte completa:** o baseline declarado (1036/3533/1F+11E/0skip = 1025/3500 + 11 runs exatos) é plausível e consistente com a contagem dos testes novos (3 D1 + 5 D2 + 3 D3 = 11). Não re-executei a suíte inteira (paraleliza por arquivo e não é discriminadora para contaminação cross-arquivo); a checagem de regressão foi feita pelo A/B serial acima + o probe de equivalência (104 pares).

---

## Apontamentos

### 🟡 Sugestões de melhoria

| ID | Descrição | Arquivo:linha | Tarefa |
|---|---|---|---|
| 🟡1 | **O agregado `unidade_inelegivel` sobre-reporta** vs o PORO: ele varre TODAS as lotações de todos os alvos ativos e flagra qualquer unidade inelegível-com-gestor na cadeia, **sem** respeitar a precedência do PORO (passos 1/3/4 retornam ANTES do passo 5 e o PORO nunca loga). **Reproduzido por probe:** (a) alvo onde o PORO libera por `gestor_individual` (passo 4) → PORO loga 0, scope loga 1; (b) alvo = o próprio gestor (passo 1) → PORO loga 0, scope loga 1. A direção é **conservadora** (falso-positivo de negação), não um falso-negativo de segurança, e a chave `unidade_ids` (agregada, sem par alvo×unidade) torna-se ambígua no shadown. **Correção recomendada (para a 29.7/shadow):** restringir a varredura à condição do próprio `condicao_hierarquia` (a MESMA subquery de lotação principal vigente correlacionada ao alvo), em vez de "qualquer lotação com a cadeia flagrada". Alternativa aceitável: documentar explicitamente que o agregado é um **superconjunto** e ensinar o shadow a tratar `unidade_ids` como "há negação D6 em alguma lotação", nunca como "por alvo". | `frequentadores_visiveis.rb:315-350` | D2 / alimenta shadow 29.7 |
| 🟡2 | A `iteration_chore` afirma que o agregado "reproduz a **condição exata de `hierarquia?`**". A condição D6 *dentro* da cadeia é fiel, mas a **precedência da cascata** (passo 5 só é alcançado se 1/3/4 não casarem) **não** é reproduzida — daí o 🟡1. Ajustar a redação para "condição D6 exata da cadeia; precedência de cascata não replicada (o agregado é superconjunto)". | `docs/progress/iteration_chore_debitos_pre_29_7.md:97` | doc |

### 🟠 Sugestões de qualidade / débito

| ID | Descrição | Arquivo:linha | Tarefa |
|---|---|---|---|
| 🟠1 | O teste de propriedade (`test "propriedade: ..."`) assere os veredictos com `assert_operator verdadeiros, :>, 0` / `falsos, :>, 0` — **não fixa** o 104/34/70/0. Foi por isso que o agente precisou de um probe externo para medir os números. Congelar as contagens exatas no teste daria a mesma discriminação sem probe (a 29.6 já registrava o número). Não bloqueia (o teste de propriedade atual já reprova divergências), mas o número-canônico vira regressão detectável. | `test/models/frequentadores_visiveis_test.rb:56-57` | D2/29.6 |
| 🟠2 | O teste de propriedade não é o único guard: o arquivo tem hoje 23 casos, mas o **contrato de equivalência (104/34/70/0)** só está fixado como número em documento, não em asserção. Ver 🟠1. Sem ação bloqueante. | `test/models/frequentadores_visiveis_test.rb` | D2/29.6 |

### 🟢 Elogios

| ID | Elogio | Tarefa |
|---|---|---|
| 🟢1 | Correção do bug de 3-valued logic (`COALESCE`) é **exemplar**: achado no caminho, provado por mutação e virado lição em `lessons.md` com o raciocínio de segurança (`FALSE` vs `TRUE` no `COALESCE`). | D2 |
| 🟢2 | D1 fecha o contrato **estreitando** o `@param` E adicionando fail-closed auditável — as duas metades coerentes com o alvo real (`TimeRecord#user`), sem sobre-generalizar. | D1 |
| 🟢3 | D3 ataca o buraco de cobertura com a asserção no **nível do contrato do chamador** (por pessoa), não no detalhe interno (por vínculo) — é o que a 29.7 consome. | D3 |
| 🟢4 | Reuso dos fragmentos `unidade_elegivel`/`path_valido` no agregado: uma só definição de "inelegível" (não introduz segunda regra). | D2 |
| 🟢5 | Higiene: `credentials.yml.enc`/`.ruby-version`/`.tool-versions` intocados; `application.css` temporário (usado pela suíte) é gitignored e não aparece no status; log/test.log e tmp/cache fora do commit. | — |
| 🟢6 | Nenhuma regressão: `pode_ver?` da 29.4, `Ability`, motor de cálculo e o conjunto devolvido pelo scope intactos (`frequentadores_visiveis.rb` tem **zero** consumidor de produção hoje — só testes). | — |

---

## Falsos positivos refutados (investigados e descartados)

1. **"Os testes D2 após `private` (linha 327) são silenciosamente ignorados."** — **REFUTADO**. O macro `test` do ActiveSupport usa `define_method`, que em Ruby cria métodos **públicos independentemente do `private` da classe**. Verificado em 3 frentes: (a) fonte do minitest 6.0.6 (`methods_matching` filtra `public_instance_methods`); (b) reprodução mínima em Ruby puro (`define_method` após `private` → público); (c) execução real: `-n /D2/` = **5 runs** e probe de introspecção = `public=5 private=0`. **Não há testes pulados, não há gap de cobertura.** (Nota de estilo: mover os testes D2/D3 para antes do `private` melhora a legibilidade, mas não é blocker.)
2. **"Contaminação cross-arquivo do `private`."** — **REFUTADO**. O `private` é escopado à classe; não vaza para outros arquivos de teste. Os testes após `private` são registrados na própria classe e aparecem no contador.
3. **"`pessoa_do_usuario` do PORO não loga `pessoas_indisponivel`."** — **REFUTADO**. `autorizacao_frequencia.rb:222` encaminha para `resolver_pessoa_por_user(usuario, papel: :usuario)` (`:232`), que é quem loga. O scope replica o **mesmo caminho** (log avulso no `rescue` de `pessoa_do_usuario`).
4. **"O agregado introduz N+1 / volume de log por linha."** — **REFUTADO**. 1 query fixa por chamada; 1 evento por chamada quando há negação; teste de contagem de queries passa (constante com +20 frequentadores).

---

## Riscos

- **Baixo.** D1/D2 aditivos; D2 não altera o conjunto devolvido pelo scope (equivalência 104/34/70/0 mantida); D3 é só teste.
- **Único risco novo = 🟡1** (sobre-reporte do log agregado). Impacto contido ao shadow mode da 29.7 (leitura), direção conservadora. **Não bloqueia o commit**; recomenda-se alinhar com a 29.7 (que consome o evento) antes de ligar a flag.

## Ações corretivas

- [ ] (Opcional, não-bloqueante) Endereçar 🟡1 na 29.7/shadow: restringir o agregado à condição correlacionada ao alvo, ou documentar o superconjunto e ajustar o consumo.
- [ ] (Opcional) Corrigir a redação de `iteration_chore...:97` (🟡2).
- [ ] (Opcional) Congelar 104/34/70/0 no teste de propriedade (🟠1).

## Pré-requisitos de commit (para o Code Specialist / coordenador)

- Stage **seletivo** apenas de: `api-ponto/app/models/elegibilidade_desconsideracao.rb`, `api-ponto/app/models/frequentadores_visiveis.rb`, os 2 testes, `docs/governance/lessons.md`, `docs/progress/iteration_chore_debitos_pre_29_7.md` e **este** relatório.
- **Excluir** `api-ponto/log/test.log` e `api-ponto/tmp/cache/*` (trackeados, sujados pelos testes).
- `COMMIT_MODE=manual`: o revisor **não** commitou. Não há blocker técnico — pode commitar.
