# ADR-0008: Semântica de estado do gestor individual (`ativo`) e reconciliação de identidade com o legado

> **[⌂ Home](../README.md)**

## Status

Aceito (CTO, 2026-09-30). Decorre do review da Tarefa 29.3 (`docs/quality/review_report_29_3.md`),
fecha as duas ressalvas submetidas ao CTO e o achado 🟡2 (`GestorIndividual#ativo` order-dependent).
Orienta a **29.3-D1/D2/D3** (patches de correção) e o consumo em **29.4/29.5/29.6**.

## Contexto

- A Tarefa 29.2 separou o que o legado guardava numa **única** linha (o par gestor→gerido) em **duas**
  entidades no Frequencia: `GestorIndividual` (uma linha por **PESSOA-gestor**) e
  `GestorIndividualGerenciado` (o par). A 29.3 importa o legado e precisa decidir como derivar o
  estado (`ativo`) da PESSOA a partir de N vínculos.
- **Evidência do legado (lida na fonte, não suposta):** `intranet/src/modules/presenca/beans/GestorIndividual.java`
  mapeia `@Table("presenca_gestorindividual")` com `@OneToOne vinculado_id` (o gestor) + `frequentador` (o gerido)
  e os campos `ativo` / `dataExclusao` / `dataCriacao` **na mesma linha**. `GestorIndividualServices.java`
  e `GestorIndividualDao.java` só operam a **linha do PAR** (`find(vinculado, frequentador)`,
  `listarFrequentadoresDo(vinculado)` com `gi.ativo=true AND gi.dataExclusao IS NULL`). O legado **não tem
  a entidade "gestor" como objeto próprio** — o "gestor" é o campo `vinculado_id` de cada linha.
- A autorização do legado (`RegistroFrequenciaValidator.java:65/150/167`) é literalmente *"existe **alguma**
  linha ATIVA do gestor X para o frequentador Y"* (`isVinculadoGestorDoFrequentador`).
  O PRD (§2.5/§3, passo 4) confirma: *"Um frequentador pode ter múltiplos gestores individuais ativos"*.
- **Consequência factual:** a operação da 29.3 é uma **AGREGAÇÃO** que não tem análogo no legado. Não existe
  estado do gestor no legado para "ler de outro lugar" — a opção (c) do achado 🟡2 é **descartada por evidência**.
- O `aplicar_estado` do serviço (`importar_gestores_individuais_service.rb:235-238`, chamado para o gestor via
  `aplicar_gestor:218` e para o vínculo via `aplicar_vinculo:226`) reescreve o `ativo`/`data_exclusao` do
  gestor **a cada linha**. Como o mesmo gestor aparece em N linhas e a ordem do payload é a ordem que o
  **Intranet** devolve (nada no código a fixa), a "última linha vence" → `GestorIndividual#ativo` é
  **order-dependent** (reproduzido pelo Code Reviewer: `[ativa, excl1, excl2]`→`false`; `[excl1, excl2, ativa]`→`true`).
- Duas estruturas de identidade **distintas** convivem: o vínculo do gestor em Pessoas (`id_vinculo_gestor`) e o
  vínculo do par no Intranet (`id` da linha). O CPF é a ponte entre elas.

## Alternativas Consideradas

### Alternativa A — `ativo` do gestor = "algum vínculo ativo" (opção (b)), derivado pós-loop
- **Prós:** fiel à autorização do legado (passo 4 = *algum* par ativo); 1:1 com o legado no atributo `ativo`
  do **par** (que fica preservado por linha); determinístico (independe da ordem); coerente com o índice
  UNIQUE parcial `WHERE ativo` (evita colisão na reimportação); fecha o Bug 16 ao usar `.ativos`.
- **Contras:** o estado do gestor deixa de ser um campo "próprio" e passa a ser projeção; exige recálculo
  pós-loop no serviço.

### Alternativa B — `ativo` do gestor = "TODOS excluídos" (opção (a)); inativo só se nenhum ativo
- **Constras:** idêntica à A para a autorização, mas com rótulo invertido; não muda nada materialmente.
  Adotamos A e registramos que "inativo = nenhum ativo" (mesma coisa). Não é alternativa real.

### Alternativa C — ler o estado do gestor no legado (opção (c))
- **Contras:** **inexiste** no legado (ver Contexto). Descartada por evidência, não por preferência.

### Alternativa D — manter "última linha vence"
- **Contras:** não é uma regra — é a ausência de regra, acoplada à ordem de uma API de terceiro. Impacto hoje
  baixo (a tela não lê `ativo`), mas a 29.4/29.6 dependem de "gestor ativo" (ADR-0007). Descartada.

## Decisão

> **ADOTAMOS A ALTERNATIVA A.** A semântica de `GestorIndividual#ativo` é **projeção derivada dos vínculos**.

Regras:

1. **Semântica de `ativo` do GESTOR (fonte única):** `ativo = true` **sse existe ≥ 1
   `GestorIndividualGerenciado` ATIVO** apontando para ele; `false` **sse todos inativos** (ou nenhum vínculo
   — gestor recém-criado/órfão). O estado canônico do par é `gestor_individual_gerenciados.ativo`
   (preservado **1:1** por linha do legado); o do gestor é a **agregação**.
2. **`data_exclusao` do gestor reflete o conjunto de vínculos ATIVOS** — a exclusão mais recente entre eles;
   sem vínculos ativos, mantém a última data (ou `nil` se nunca excluído). **Nunca** "a `data_exclusao` da
   última linha do payload". Elimina o order-dependence (review 🟡2) por regra explícita.
3. **Reconciliação determinística pós-loop:** o `ativo`/`data_exclusao` do gestor é calculado **depois** de
   processadas todas as linhas do gestor (ou recalculado em lote para os gestores tocados), via
   `GestorIndividualGerenciado.ativos.where(gestor_individual:)` / `exists?(ativo: true)` — o que também
   **usa o índice parcial** (fecha o Bug 16, que é débito de 29.4/29.6 e agora também de 29.3-D1).
4. **Identidade do gestor — proibido comprometer identidade por premissa não verificada.** `encontrar_gestor`
   casa por `id_legado` do gestor (**primário**, quando presente) e, como ponte, por `gestor_cpf`. Se o
   `gestor_cpf` resolvido **divergir** do `gestor_cpf` do gestor casado por `id_legado`, a linha vira
   **`nao_resolvido` com motivo de conflito de identidade** — **não** reescrever o CPF do gestor existente (o
   código hoje o sobrescreve em `:213`) e **não** tocar no `gestor_user` dele (evita auto-autorização na
   cascata via id reaproveitado). A guarda é defensiva e barata (segunda condição).
   - ⚠️ **Evidência do legado:** `id_vinculo_gestor` é o **`id` de `tjpi_vinculo`** (o vínculo/contrato, não a
     pessoa) — `intranet/src/modules/tjpi/beans/Vinculo.java` (@Id `@GeneratedValue(strategy = IDENTITY)`) e
     `pessoas2/app/models/intranet/vinculo_intranet.rb#codigo_de_para = @vinculo_intranet['id']`. Como a PK é
     IDENTITY (auto-incremento), um **vínculo novo nunca reaproveita um id antigo**; e o legado guarda o gestor
     por `vinculado_id` (o Vinculado/PESSOA) enquanto o payload expõe o id do vínculo — **logo `id_vinculo_gestor`
     não é "único por pessoa"** (uma pessoa pode ter múltiplos vínculos ⇒ múltiplos ids). A reciclagem literal
     do id por OUTRA pessoa não é o risco principal; o risco real é a **assimetria vínculo↔pessoa** e o
     reaproveitamento do `id_legado` pelo próprio gestor em cenário de exoneração/novo vínculo. **A guarda
     (CPF deve concordar com o `id_legado`) torna a decisão robusta independentemente disso.**
5. **Reativação de gestor após exclusão legada:** a reconciliação de identidade **não** pode mais "reancorar"
   o gestor **em toda linha** (isso criava a colisão do índice parcial). Nova regra de guarda:
   `id_legado` do gestor reancora **só na criação** ou quando a linha legada **recria** um vínculo após
   exclusão legada (`id_vinculo_gestor` ausente/zero/inválido). Linha cuja `id_vinculo_gestor` está **presente**
   casa **só** por `id_legado` do gestor (`nil` se não houver). Fecha o furo 🔴 **F1** (reimportação reactivando
   vínculo de gestor cuja linha traz `ativo: true` colidiria com `index_gestor_individual_gerenciados_on_par_ativo`).
6. **Nome do gestor — marcador explícito de sistema.** Quando o nome **não** vem do Pessoas, gravar um texto
   **explicitamente de sistema**, distinguível de nome real e **substituível** numa reimportação com o Pessoas
   de volta: `"(sem nome — CPF 12345678901)"`. Substitui o fallback atual `"Gestor individual <CPF>"`
   (`service:284/287`), que se parece com dado real e **gruda** por `||=` (review 🟠1). `nome` continua
   obrigatório no model; o marcador é a representação canônica de "nome não resolvido" — a linha nunca é descartada.
7. **`nome` só é reescrito quando a origem é o Pessoas** (nome real "ganha" do marcador; o marcador **não**
   sobrepõe um nome real já gravado por outro caminho).
8. **Chaves do payload legado — verificar o casing no ambiente real (🔴 F2, achado adicional do CTO).**
   O único consumidor conhecido do endpoint, o Pessoas2 (`pessoas2/app/models/gestao_individual.rb:23`), lê as
   datas como **`json["dataCriacao"]`/`json["dataExclusao"]` (camelCase)**, enquanto a doc da gem
   (`sticapi_client/lib/sticapi_client/intranet.rb:42`) e o serviço da 29.3 leem **`data_criacao`/`data_exclusao`
   (snake_case)**. Como o serviço só ingere um dump (o parse tem stub), os testes **nunca exerceram o payload
   real**: se a chave real for camelCase, `momento_exclusao` é sempre `nil` ⇒ **todo registro excluído no legado
   entra ATIVO sem `data_exclusao`** — corrupção silenciosa de `ativo`, o pior caso. **Ação (bloqueia a
   importação real em produção, não o commit):** provar o casing com **uma chamada real/amostra** de
   `gestores_individuais` (ou o código do endpoint Sticapi, ausente do repo local) **antes** de rodar a
   importação; normalizar a leitura para aceitar ambos os casings (`linha[:data_criacao] || linha["dataCriacao"]`)
   e adicionar teste com o payload real.
9. **`gestor_cpf` tem `format: /\A\d{11}\z/` (sem máscara)**, enquanto o payload que o Pessoas2 casa usa
   **`codigo_de_para`** (id do vínculo) no fallback — o serviço normaliza (`normalizar_cpf`), mas o `id` do
   payload pode chegar como string/float; a normalização na borda (⚪14) deve cobrir o tipo, não só `""`.

## Consequências

### Positivas
- O `ativo` do gestor tem **semântica definida e determinística**, fiel ao legado (passo 4 = *algum* vínculo
  ativo) — a 29.4/29.6 podem consumi-la sem ambiguidade, e o ADR-0007 deixa de ter um ponto em aberto.
- O atributo `ativo` do **par** preserva 1:1 o dado do Intranet; a agregação não corrompe o histórico.
- A guarda de identidade remove o risco silencioso de auto-autorização na cascata.
- O order-dependence e a colisão de reimportação 🔴 F1 ficam com **regra explícita e teste**.

### Negativas / Trade-offs
- A 29.3 ganha **3 patches** (D1 semântica+testes; D2 guarda de identidade+teste; D3 marcador de nome+teste)
  que entram **antes** da 29.4/29.6.
- O recálculo pós-loop é O(N) adicional no serviço — aceitável para o volume; pode ser feito em lote.
- A projeção do `ativo` do gestor não é validada por constraint de banco (é derivada); quem gravar o gestor
  **fora** da importação precisa recalcular (documentado; a tela não tem caminho de escrita hoje).

### Neutras
- Não altera migrations aplicadas, nem o schema do Pessoas, nem gem alguma.
- Não altera a idempotência da 29.3 (2ª execução = 0 criações) nem o mapeamento `id_legado` do par.

## Compliance

- **29.3-D1/D2/D3** implementados e testados **antes** de 29.4/29.6.
- Nenhuma projeção de `ativo` pode depender da **ordem** do payload; teste obrigatório de gestor com
  vínculos ativos **e** inativos em ordens opostas.
- 29.4/29.6 não podem ler `GestorIndividual#gerenciados` cru (Bug 16); usar `.ativos`.
- O item "semântica de `ativo` derivada + determinismo por ordem" entra no `structural-conformity-checklist`.

## Notas

- ADRs relacionados: 0007 (soft-delete do vínculo, invariante de auto-gerência), 0001 (integração com Pessoas).
- Fontes do legado: `intranet/src/modules/presenca/beans/GestorIndividual.java`,
  `.../services/GestorIndividualServices.java`, `.../dao/GestorIndividualDao.java`,
  `.../validators/RegistroFrequenciaValidator.java`.
- Fontes do Frequencia: `docs/quality/review_report_29_3.md`;
  `api-ponto/app/services/importar_gestores_individuais_service.rb`; migrations `20260929120000`/`20260929130000`;
  PRD §2.5/§3; `docs/progress/iteration_29.md` (seção `🧭 Rulings do CTO — 29.3`).
- Modelos: `api-ponto/app/models/gestor_individual.rb`, `gestor_individual_gerenciado.rb`,
  `app/models/concerns/desativavel.rb`.
