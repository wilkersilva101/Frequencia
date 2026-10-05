# Relatório de Revisão — Code Reviewer (Tarefa 29.6)

> **Branch:** `feature/demanda-29-6-frequentadores-visiveis` (base `integration/sprint-29` @ `43b7d84`)
> **Data:** 2026-10-02
> **Propósito:** Revisar o scope `frequentadores_visiveis(usuario)` — em especial a **verificação de equivalência** (teste de propriedade) entre o scope SQL (`FrequentadoresVisiveis`) e o PORO `AutorizacaoFrequencia#pode_ver?` (29.4, fonte da verdade).
> **Tarefas revisadas:** 29.6 (Sprint 29). Insumos: 29.4 (PORO), 29.7 (contrato do nome), ADR-0006/0007/0008.
> **Arquivos alterados:** `app/models/frequentadores_visiveis.rb` (novo, 268 l.), `test/models/frequentadores_visiveis_test.rb` (novo, 500 l.), `app/models/pessoas/vinculo.rb` (+14 l., aditivo), `docs/progress/iteration_29.md` (status da 29.6).

## Veredito

**✅ APROVADO — 0 Blockers.** Bloqueio de commit: **nenhum** (`COMMIT_MODE=manual`; ver "O que impede o commit").

Blockers: 0 | Sugestões: 5 (Melhoria: 3 / Débito: 2) | Elogios: 6

O ponto central desta tarefa — a verificação de equivalência — foi **auditado de forma independente e é uma verificação VÁLIDA**, não teatro. As 9 armadilhas que motivaram o ceticismo foram checadas uma a uma (ver §Falsos Positivos Refutados e §Verificações Independentes).

---

## Verificações Independentes (reprodução)

Executadas no worktree `wt-29.6`, banda própria (`BUNDLE_PATH` apontando para o bundle de `Frequencia/api-ponto`), banco espelho `frequencia_pessoas_espelho_test` já carregado.

| # | Alegação do agente | Resultado independente | Status |
|---|---|---|---|
| 1 | Scope **não** é tautológico (não chama o PORO) | `grep pode_ver\|AutorizacaoFrequencia app/models/frequentadores_visiveis.rb` → **só comentários** (l. 2,3,9). Zero chamada em código. | ✅ confirmado |
| 2 | Guardas anti-degenerescência | `test:56-57` `assert_operator :>, 0` nos dois veredictos + teste dedicado `:63`. | ✅ confirmado |
| 3 | **104 pares → 34 T / 70 F, 0 divergências** | Probe instrumentado: `TOTAL_PAIRS=104 TRUE=34 FALSE=70 DIV=0`. | ✅ confirmado |
| 4 | `vinculo.rb` puramente aditivo | `git diff 43b7d84` → `14 ++++++++` / `0 -`, só o método de classe. | ✅ confirmado |
| 5 | Contagem de queries constante | Probe: gestor **8 → 8** (com +20 frequentadores); role geral **3**. Constante. | ✅ confirmado |
| 6 | Suíte-alvo | `frequentadores_visiveis_test.rb` → **15 runs / 53 assertions / 0F / 0E**. | ✅ confirmado |
| 7 | A/B serial (dashboard + 29.4 + 29.6) em seeds 1/7/42/6000 | **58 runs / 173 assertions / 0F / 0E** em todas. | ✅ confirmado |
| 8 | Suíte completa | **1001 runs / 3458 assertions / 1F + 11E / 0 skip**. | ✅ confirmado |
| 9 | Assinaturas das falhas | 11 errors = 9× `Users::SessionsController` + 2× `Users::PasswordsController` (`private method 'redirect_to'`); 1 failure = timezone em `PresencaEndpointsTest`. **0 vindas dos arquivos da 29.6.** | ✅ confirmado |
| 10 | `test/models` / `test/controllers/admin` | **404/972/0/0** e **174/984/0/0**. | ✅ confirmado |
| 11 | RuboCop / Zeitwerk | 3 arquivos **0 offenses**; `zeitwerk:check` "All is good!". | ✅ confirmado |
| 12 | Mutation testing (amostra M4/M7/M9 + path_valido) | M4 (geridos sem `.ativos`) → 1F; M7 (sem guard de auto-referência) → 2F; M9 (ancestral sem elegibilidade) → 2F. Todas **mortas de verdade**. | ✅ confirmado |

### Distribuição dos 104 pares (medida — responde ao ponto de atenção 1)

```
TOTAL 104 = 34 T / 70 F / 0 divergências
POR USUÁRIO (T/F):
  :geral                  13T/0F   (role geral → todos)
  :admin                  13T/0F   (admin    → todos)
  :gestor                  6T/7F   (próprio + 1 gerido + hierarquia)
  :terc                    1T/12F  (só o alvo terceirizado)
  :gestor_sobe_inativa     1T/12F  (hierarquia acima de unidade inativa)
  :inativa                 0T/13F  (unidade inelegível não libera) — controle negativo
  :extinta                 0T/13F  (idem)                          — controle negativo
  :outro                   0T/13F  (sem via nenhuma)               — controle negativo
POR FREQUENTADOR (T/F) — nenhum rótulo é trivial:
  :proprio [3,5] · :terceirizado [3,5] · :gerido [3,5] · :gerido_inativo [2,6]
  :hierarquia [3,5] · :negado [2,6] · :sub_inativa [3,5] · :sub_extinta [3,5]
  :ancestral_ausente [3,5] · :corrompido [2,6] · :path_repetido [2,6]
  :auto_referencia [2,6] · :abaixo_de_inativa [3,5]
```

**Não há concentração ilusória.** Os `true` distribuem-se por 5 usuários distintos e pelos 5 passos da cascata; os `false` vêm tanto de usuários com acesso parcial (`:gestor` 7F, `:terc` 12F) quanto de controles negativos puros. Nenhuma linha é `[13,0]`/`[0,13]`. A cobertura é real.

### Verificação legítima item a item (ponto de atenção 3)

A comparação é legítima: para cada par, `escopo_ids.include?(vinculo.id)` (scope, por alvo) vs `AutorizacaoFrequencia.new(usuario).pode_ver?(alvo)` (PORO, por alvo — o PORO **é** por alvo, não por conjunto). O teste avalia os **mesmos 8×13 pares**, na mesma fixture, no mesmo processo, e materializa a decisão do scope como predicado por alvo. Não é uma comparação assimétrica acidental. O `vínculo` do scope é o mesmo objeto que ancora o `alvo` do PORO pelo CPF (`cena[:frequentadores][r].pessoa.cpf → cena[:alvo_para]`), inclusive nos dois casos de multipessoalidade por CPF (assert em `test:239-247`).

---

## Os 4 Critérios de Aceite — um a um

| # | Critério | Veredito | Evidência |
|---|---|---|---|
| 1 | **D6 replicada no SQL** (inelegível não libera; ausente não interrompe) + `.distinct` | ✅ **Cumprido** | SQL replica `elegivel?` (`unidade_elegivel`, l.237-241) tanto no self (l.177) quanto nos ancestrais (l.181-188); `path_valido` (l.247-256) fecha corrompido; ancestral ausente = `JOIN` que não casa e a subida continua. 6 testes D6 diretos no scope (l.97-153). M9 e `path_valido→TRUE` **mortas** (2F e 9E). `.distinct` presente nos 2 caminhos. |
| 2 | **Scope SQL** (não filtro em Ruby) combinando os 5 passos | ⚠️ **Cumprido com ressalva de escopo** | Passos 3 (terceirizado) e 5 (hierarquia) são **SQL puro** (`EXISTS`/`IN`/`unnest`, sem loop por linha); o resultado final é uma `ActiveRecord::Relation` de `Pessoas::Vinculo`. Passos 1/4 são resolvidos em Ruby **apenas porque** `users` (banco primário) e `pessoas`/`vinculos` (espelho) são Postgres distintos — **limite real confirmado** em `config/database.yml` (dois blocos, sem FK/JOIN cross-database). Ver 🟡1. |
| 3 | **Resultado idêntico a `pode_ver?` item a item** (teste de propriedade) | ✅ **Cumprido** | 104 pares, 34/70, 0 divergências (reproduzido). Tautologia descartada (o scope não chama o PORO). Não-degeneração provada (guardas + distribuição). |
| 4 | **Sem N+1** (teste de contagem de queries) | ✅ **Cumprido** | Invariante `assert_equal` 8→8 com +20 frequentadores; teto `<= 10` é guard secundário. Nenhum loop por linha no scope. |

---

## Blockers (🔴)

Nenhum.

---

## Sugestões (🟡)

| ID | Descrição | Tarefa(s) | Impacto/Nota |
|---|---|---|---|
| 🟡1 | **Cobertura de propriedade parcial no espaço de vínculos de uma pessoa.** A fixture coloca **exatamente 1 vínculo ativo por pessoa-alvo**. Medido por probe: uma pessoa com 2 vínculos ativos (1 Não-Terceirizado + 1 Terceirizado) sob a role `visualiza_terceirizados` → o scope devolve **só o vínculo Terceirizado**, enquanto o PORO **aprova a pessoa inteira** (`poro_alvo=true`). **Não é divergência de regra:** o PORO responde por *pessoa* e o scope devolve *vínculos* — a união dos vínculos aprovados da pessoa = conjunto que o PORO aprova. O contrato item-a-item está correto para a chave *pessoa*, que é a que o chamador usa (listagem filtra por `pessoas.cpf` completo; a 29.7 consome `accessible_by`). O teste, porém, **não exercita o caminho multi-vínculo** (o caso existe e foi implementado — `subquery_tipos_terceirizado` casa qualquer vínculo Terceirizado ativo). | 29.6 | **Melhoria**, não-débito. Sugestão: adicionar 1 alvo com 2 vínculos ativos e asserir o contrato **por pessoa** (`escopo.joins(:pessoa).where(pessoas:{cpf:}).exists? == pode_ver?(pessoa)`), documentando que o scope é de vínculos. |
| 🟡2 | **`.path_valido` sem clamp de profundidade.** A regex `^\d+(/\d+)*$` não limita o comprimento; um `ancestry` corrompido muito longo é integralmente castado (`::bigint[]`) e `unnest`ado. Não há corrupção fora desse padrão que ainda passe a regex (bem guardado). Risco é apenas de profundidade absurda. | 29.6 | **Débito de robustez.** Sugestão: clamp de profundidade (ex.: `array_length <= N`) ou `CHECK` na origem; documentar como defensivo. |
| 🟡3 | **Teste estrutural do `.distinct` é o único guard do critério 1.** Remover o `.distinct` inteiro quebra **apenas** esse teste (1F) — os demais ficam verdes (equivalência comportamental confirmada por probe). É um guard legítimo **contra regressão futura** (um `LEFT JOIN` multiplicador), mas hoje só verifica a **string** `SELECT DISTINCT`. | 29.6 | **Melhoria**, aceitável como está (ver §`.distinct`). Sugestão: quando existir cenário que multiplique linhas, trocar por teste comportamental (`ids.uniq == ids`); hoje o teste `:173` já cobre o caso fraco. |
| 🟠1 | **Simetria de identidade do gestor (passo 4) — as duas vias não são gêmeas.** O PORO exige `alvo_user_id` presente (só alvos `User`) e usa `escopo.where(user_id: alvo_user_id)`; o scope deriva o **conjunto de CPFs geridos** e casa por `pessoas.cpf IN (...)` (sem exigir `User` para o alvo). Essas duas vias podem divergir se existir um vínculo gerido cujo `User` tenha CPF que também pertença a outra pessoa/vínculo no Pessoas. **Não é alcançável na fixture** (CPFs únicos por construção) e exige dado anômalo (mesmo CPF em 2 pessoas/vínculos). | 29.6 | **Débito de invariante de dados**, documentar. Sem exploração realista conhecida. |
| 🟠2 | **`log_unidade_inelegivel` (PORO) sem espelho no SQL**, e o scope **não loga `ancestral_ausente`** (o PORO loga via `cadeia_ascendente`). O critério não exige logs no scope; a 29.7/shadow mode pode querer contadores de negação. | 29.6 / 29.7 | **Débito de observabilidade.** Registrar para a 29.7. |

---

## Elogios (🟢)

| ID | Elogio | Tarefa(s) |
|---|---|---|
| 🟢1 | **A verificação de equivalência é genuína.** Duas implementações independentes da mesma cascata; o scope nunca chama o PORO; 104 pares com 0 divergências e distribuição não-degenerada. É o produto da tarefa, e ele existe. | 29.6 |
| 🟢2 | **Distribuição por passo medida e saudável** (8 usuários × 13 alvos; nenhuma linha trivial). O teste de propriedade não é um "tudo verde por construção". | 29.6 |
| 🟢3 | **D6 implementada nos dois planos (Ruby e SQL) e provada nos dois.** Os 4 controles negativos são usuarios reais da fixture e vêm com veredicto negativo explícito. | 29.6 |
| 🟢4 | **Mutation testing com mortes reais** (M4/M7/M9 e `path_valido` reproduzidas e confirmadas). As guardas dos bugs 1/2 do `cadeia_ascendente` têm testes que as matam. | 29.6 |
| 🟢5 | **Higiene impecável:** `credentials.yml.enc`/`.ruby-version`/`.tool-versions` intocados; `application.css` temporário gitignored; `log/test.log` + `tmp/cache/*` fora do escopo; RuboCop 0 offenses; Zeitwerk OK. | 29.6 |
| 🟢6 | **Contrato com a 29.7 explícito e correto:** `Pessoas::Vinculo.frequentadores_visiveis(usuario)` devolve a mesma relação do object (testado por rótulo, l.218-228) e é o nome literal citado no critério da 29.7. | 29.6 / 29.7 |

---

## `.distinct` e o teste estrutural — avaliação pedida (ponto de atenção 4)

**Aceitável manter `.distinct` + teste estrutural.** Justificativa medida:

- A query atual **não** tem `JOIN` multiplicador (a hierarquia é um `EXISTS`; o filtro por CPF casa o vínculo uma única vez por linha). Confirmado: remover o `.distinct` inteiro deixa a suíte-alvo com **0F/0E** exceto o teste estrutural (1F) — ou seja, hoje o `.distinct` é **mutante equivalente**.
- Porém `.distinct` é o **comportamento correto** para um scope de listagem chamado via `accessible_by`/paginação: se um `LEFT JOIN` for adicionado no futuro (ex.: pré-carregar a lotação principal em vez do `EXISTS`), a duplicata quebraria a paginação (`offset`/contagem), exatamente o motivo citado no comentário do código e no `frequentadores_ativos` (que já usa subquery-`IN` pelo mesmo motivo).
- O teste estrutural (`assert_match /SELECT DISTINCT/`) é **fraco como asserção comportamental**, mas **legítimo como guard de intenção** — é o mesmo padrão de "teste de contrato de string" que o projeto já aceita em outros pontos. Não é teatro: ele falha de forma determinística se alguém remover o `.distinct`; e o teste `:173` (`ids == ids.uniq`) cobre a semântica no caso fraco atual.
- **Veredito:** manter. A classificação honesta do agente (mutante equivalente hoje + guard para cenário futuro) é correta e não mascara nada. Sugestão 🟡3 apenas registra o limite.

---

## A implementação híbrida (Ruby passos 1/4, SQL passos 3/5) — ponto de atenção 6

**Limite real, não desculpa.** `config/database.yml` define dois blocos distintos (`primary` = `api_ponto_*`; `pessoas` = espelho do Pessoas), ambos Postgres, **sem** `joins` cross-database possível no ActiveRecord e **sem** FK entre os dois. A regra de negócio continua em um só lugar (`condicoes_liberacao`, o SQL); os mini-fragmentos de `users`/`gestor_individual_gerenciados` (l.98-133) são leitura do banco primário análoga ao PORO, não uma segunda regra. O critério "scope SQL, não filtro em Ruby" é satisfeito no sentido relevante: **o filtro sobre o Pessoas é SQL** (o que evita carregar a tabela em Ruby); os passos 1/4 apenas reduzem-se a uma lista de CPFs/ids que entra como `IN (...)` — nenhum registro do espelho é filtrado em Ruby. A decisão está documentada no cabeçalho do arquivo (l.14-23) e o desenho é coerente com `Pessoas::Vinculo.frequentadores_ativos`, que usa o mesmo padrão de "listas de CPF do User local".

---

## Contagem de queries (ponto de atenção 5)

Confirmada **constante**: 8 → 8 (poucos → 20 frequentadores) para o gestor; 3 para role geral (curto-circuito sem os passos de identidade). As 8 = 3 checagens de role + 1 subquery de geridos + 1 leitura de CPFs + 1 `por_user` do gestor + ... (as demais são das duas consultas de role de usuário). O teto `<= 10` é guard secundário: mesmo frouxo, ele **falharia** sob N+1 real (um `SELECT` por linha com 20+ linhas iria a 20+, bem acima de 10). O invariante primário (`assert_equal poucos, muitos`) é o que realmente discrimina. Aprovado.

---

## Mutation testing (ponto de atenção 7)

Reproduzidas as mais críticas, todas **mortas de verdade** (não por erro incidental):

- **M4** (geridos sem `.ativos`): 1F no teste de propriedade (`gerido_inativo` passa a visível) — discrimina.
- **M7** (sem guard de auto-referência): 2F — mata tanto o teste de auto-referência pura (l.147) quanto deixa o gestor da raiz liberar. Confirmado.
- **M9** (ancestral ignora elegibilidade): 2F — o gestor de unidade ATIVA acima de uma INATIVA volta a liberar; também o controle negativo. Confirmado.
- **`path_valido → TRUE`**: **9 errors** — a comparação `id = ANY(string_to_array('raiz/abc')::bigint[])` levanta `PG::InvalidTextRepresentation`. Morte confirmada (o `"TRUE"` é texto, não SQL, mas o cast inválido já derruba). Ressalva: a morte se dá por **exceção de cast**, o que é análogo ao PORO (que também só valida o formato), mas o "esperado" pelo teste (`assert_not_includes`) não distingue corrupção de erro. Não muda o veredito.
- **`.distinct` removido**: só o teste estrutural falha (ver §`.distinct`) — mutante equivalente, como o agente admitiu.
- **Batches com regex que não aplicaram:** verifiquei que os alvos das mutações que reproduzi (M4/M7/M9) são aplicáveis por `str_replace` exato — nenhuma "morte falsa" encontrada na amostra. As 2 regex em batch que o agente citou como não-aplicadas são plausivelmente as que exigiam escape de `\/` (como a minha 1ª tentativa de M7, que não aplicou e eu corrigi). Recomendo, no entanto, que o agente **não** dependa de batch regex para mutações com caracteres escapados: risco de "mutação não aplicada = falsa morte".

---

## Falsos Positivos Refutados (checados explicitamente)

1. **"O scope delega ao PORO" (tautologia)** — **REFUTADO**. O scope não referencia `AutorizacaoFrequencia`/`pode_ver?` em código algum (só comentários). As implementações são independentes.
2. **"O teste de propriedade não discrimina (tudo true/false)"** — **REFUTADO**. 34 T / 70 F, distribuídos por 5 usuários e 13 alvos; guardas `:> 0` nos dois veredictos.
3. **"A comparação item-a-item é assimétrica e compara coisas diferentes"** — **REFUTADO** para a chave *pessoa* (que é a que importa); o teste ancora scope e PORO no mesmo alvo por CPF. A multipessoalidade por vínculo é o 🟡1 (melhoria), não um defeito do teste.
4. **"A implementação híbrida é desculpa para filtrar em Ruby"** — **REFUTADO**. O limite cross-database é real (`database.yml`, 2 blocos); o filtro sobre Pessoas é SQL; os passos 1/4 só montam listas `IN`.
5. **"O teto `<= 10` é frouxo demais para pegar N+1"** — **REFUTADO** para o cenário real (+20): o invariante primário `assert_equal` pega qualquer crescimento por linha; o teto falharia também.
6. **"A suíte completa paraleliza e não é discriminadora para contaminação cross-arquivo"** — **CONFIRMADO o alerta**, mitigado: o A/B **serial** em 4 seeds (1/7/42/6000) deu 58/173/0F/0E em todas. O `remove_method` destrutivo foi corrigido em `eb38b1e`; a contaminação cross-arquivo não se manifesta.
7. **"Blip de infra (110 errors/18s)"** — **não reproduzido**. 6 execuções (alvo, 4 seeds A/B, suíte completa) todas limpas e consistentes com o baseline. Atribuo a instabilidade transitória, sem relação com o diff.
8. **"Nada regrediu (PORO 29.4 / Ability 29.7 intactos)"** — **CONFIRMADO**. `git diff 43b7d84` vazio para `app/models/ability.rb`, `autorizacao_frequencia.rb`, `pessoas/unidade.rb`, `pessoas/pessoa.rb`. `vinculo.rb` é +14/-0.

---

## O que impede o commit

**Nada.** Nenhum Blocker. O diff é aditivo:

- `app/models/frequentadores_visiveis.rb` (novo), `test/models/frequentadores_visiveis_test.rb` (novo), `app/models/pessoas/vinculo.rb` (+14/-0), `docs/progress/iteration_29.md` (status).
- **Fora do commit (obrigatório):** `api-ponto/log/test.log` e `api-ponto/tmp/cache/bootsnap/load-path-cache` (trackeados, inflam; `git add` nunca deve incluí-los). `app/assets/builds/application.css` é gitignored e foi removido ao fim desta revisão.
- **Higiene confirmada:** `config/credentials.yml.enc`, `.ruby-version`, `.tool-versions` intocados.

`COMMIT_MODE=manual` — o Code Specialist deve fazer **stage seletivo** dos 4 arquivos do escopo.

---

## Ações Corretivas (para a rastreabilidade)

- [ ] **(Opcional, 🟡1)** Adicionar 1 alvo multi-vínculo à fixture e asserir o contrato **por pessoa**, documentando que o scope devolve vínculos — fecha a lacuna de cobertura do espaço multi-vínculo.
- [ ] **(Opcional, 🟠2)** Registrar no `iteration_29.md` (seção Riscos/29.7) os débitos de observabilidade (logs de negação no scope) para a 29.7/shadow mode.
- [ ] **(Processo)** Nas mutações com caracteres escapados, preferir `str_replace` exato a regex em batch (evitar "morte falsa" por mutação não aplicada).
- [ ] **Stage seletivo e commit** dos 4 arquivos do escopo (nunca `git add -A`).
- [ ] Registrar a referência deste relatório no `docs/progress/iteration_29.md` (§Tarefa 29.6).

---

## Métricas

| Métrica | Valor medido (Code Reviewer) | Declarado pelo agente | Δ |
|---|---|---|---|
| Suíte-alvo `frequentadores_visiveis_test.rb` | 15 / 53 / 0F / 0E | 15 casos | ✅ |
| Suíte completa | 1001 / 3458 / 1F + 11E / 0 skip | 1001 / 3458 / 1F + 11E / 0 skip | ✅ idêntico |
| A/B serial (4 seeds) | 58 / 173 / 0F / 0E (todas) | 58 runs / 0F / 0E | ✅ |
| `test/models` | 404 / 972 / 0F / 0E | 404 / 972 / 0 / 0 | ✅ |
| `test/controllers/admin` | 174 / 984 / 0F / 0E | 174 / 984 / 0 / 0 | ✅ |
| Pares de propriedade | 104 = 34 T / 70 F / 0 div. | 104 = 34 T / 70 F / 0 div. | ✅ |
| Queries (gestor, poucos→muitos) | 8 → 8 | 8 × 8 (constante) | ✅ |
| RuboCop (3 arquivos) | 0 offenses | 0 offenses | ✅ |
| Zeitwerk | OK | OK | ✅ |
| Falhas vindas da 29.6 | 0 | 0 | ✅ |

**Nota comparativa de fixtures:** rodei o alvo com a **fixture reduzida** (1 vínculo por pessoa) e o A/B reportado é da mesma fixture. A lacuna multi-vínculo (🟡1) é sobre o *espaço de chaves*, não sobre uma falha de equivalência.
