# Relatório Bug Finder — Sprint 1 (Model de Estações + tela admin/estacoes)

> **Branch:** feat/estacao-ponto-model
> **Data:** 2026-08-26
> **Propósito:** Teste adversarial das tasks 1.1–1.5 (model `EstacaoPonto`, CRUD `Admin::EstacoesController`, integração do protocolo legado `presenca/*` com `EstacaoPonto` real). Rodado após code-review anterior que corrigiu 2 blockers (broken access control e regressão de `codAtivacao` legado).

## Resumo

| Métrica | Valor |
|---------|-------|
| Total de cenários testados | 19 |
| Bugs encontrados | 5 |
| 🔴 Crítico | 1 |
| 🟠 Alto | 1 |
| 🟡 Médio | 2 |
| 🟢 Baixo | 1 |
| ⚪ Info | 0 |

## Bugs por Severidade

### Bug 1 — Unicidade de `cod_ativacao` não é garantida no banco sob concorrência (case-insensitive só no app)

- Severidade: 🔴 Crítico
- RF/RN violado: RN implícita do model (`validates :cod_ativacao, uniqueness: { case_sensitive: false }`) e comentário do próprio código ("unique case-insensitive")
- Passos:
  1. Duas requisições concorrentes chegam a `Admin::EstacoesController#create` (ou uma cria via UI e outra via seed/console) com `cod_ativacao: "EST-001"` e `cod_ativacao: "est-001"` respectivamente, quase simultâneas.
  2. Ambas passam pela validação Rails `uniqueness(case_sensitive: false)`, que faz uma query de leitura antes do INSERT (clássico TOCTOU).
  3. A migration cria o índice como `add_index :estacoes_ponto, :cod_ativacao, unique: true` (ver `db/migrate/20260826150804_create_estacoes_ponto.rb:15` e `db/schema.rb:28`) — um índice único **case-sensitive** no Postgres (sem `functional index` sobre `lower(cod_ativacao)` nem `citext`).
  4. As duas linhas são inseridas com sucesso.
- Atual: Existem duas `EstacaoPonto` com o "mesmo" `cod_ativacao` (diferindo só em maiúsculas/minúsculas). `EstacaoPonto.registrar_contato` usa `find_by("lower(cod_ativacao) = ?", ...)` (model, linha 33), que passa a encontrar sempre a mesma linha (a de menor `id`/primeira inserida) — a segunda linha vira uma estação "fantasma" que nunca mais recebe heartbeat, aparece duplicada na tela `admin/estacoes` e não pode ser diferenciada da estação "viva" pelo operador.
- Esperado: Unicidade case-insensitive garantida no banco (ex: índice único funcional `unique index on (lower(cod_ativacao))`, ou coluna `citext`), eliminando a janela de corrida — a segunda tentativa deveria falhar com violação de constraint (e ser tratada como erro de validação, não como 500).
- Teste sugerido: Disparar duas threads/processos concorrentes (ou usar `ActiveRecord::Base.connection.execute` em paralelo/`Concurrent::Future`) tentando `EstacaoPonto.create!(cod_ativacao: "EST-001")` e `EstacaoPonto.create!(cod_ativacao: "est-001")` ao mesmo tempo; hoje ambos sucedem (esperado: só um sucede).

### Bug 2 — Falta de índice funcional para `lower(cod_ativacao)` gera full scan em todo request do protocolo `presenca/*`

- Severidade: 🟠 Alto
- RF/RN violado: Performance da Task 1.4 (validação/heartbeat chamada a cada requisição de `ValidarFrequentador`, `SincronizarRegistrosPonto` e `AdicioneEstacao`, inclusive o heartbeat a cada 5 min por estação segundo `documentacao-estacao-ponto.md:454`)
- Passos:
  1. `EstacaoPonto.codigo_ativacao_valido?` e `EstacaoPonto.registrar_contato` executam `where("lower(cod_ativacao) = ?", codigo.downcase)` / `find_by("lower(cod_ativacao) = ?", ...)`.
  2. O único índice existente é `index_estacoes_ponto_on_cod_ativacao` sobre a coluna crua (case-sensitive) — a expressão `lower(cod_ativacao)` não usa esse índice no Postgres, forçando *sequential scan* na tabela a cada chamada.
  3. Esses três controllers (`ValidarFrequentadorController`, `SincronizarRegistrosPontoController`, `AdicioneEstacaoController`) são endpoints de alta frequência (chamados por N estações físicas, heartbeat a cada 5 min + toda tentativa de login/sincronização), então o custo do scan se repete constantemente.
- Atual: Toda validação de `codAtivacao` faz sequential scan em `estacoes_ponto`. Hoje a tabela é pequena (POC), mas o padrão de acesso já está fixado no código antes de haver volume — não há N+1 clássico, mas há uma query sem índice de suporte num hot path.
- Esperado: Índice funcional `CREATE UNIQUE INDEX ... ON estacoes_ponto (lower(cod_ativacao))` (que resolveria simultaneamente o Bug 1 e este problema de performance).
- Teste sugerido: `EXPLAIN ANALYZE SELECT * FROM estacoes_ponto WHERE lower(cod_ativacao) = 'poc-ativacao-001';` — confirmar `Seq Scan` em vez de `Index Scan`.

### Bug 3 — Admin pode editar manualmente `ultimo_contato` pela UI, mascarando o real status de heartbeat da estação

- Severidade: 🟡 Médio
- RF/RN violado: Integridade do dado de monitoramento (RN implícita: `ultimo_contato` deveria refletir o heartbeat real via `EstacaoPonto.registrar_contato`, não uma edição manual)
- Passos:
  1. `estacao_params` em `Admin::EstacoesController` (linha 45-49) permite `:ultimo_contato` no formulário.
  2. `app/views/admin/estacoes/_form.html.erb` (linha 28-31) expõe um `datetime_field` editável para esse campo.
  3. Um administrador edita `ultimo_contato` de uma estação offline há semanas para "agora", via UI.
- Atual: A tela `admin/estacoes` passa a mostrar a estação como recém-contatada mesmo que ela esteja fisicamente desligada/desconectada — não há nenhuma distinção entre heartbeat real (vindo de `AdicioneEstacaoController`) e edição manual.
- Esperado: `ultimo_contato` (e idealmente `versao`, que também vem do heartbeat) deveria ser somente-leitura no form admin, populado exclusivamente por `EstacaoPonto.registrar_contato`.
- Teste sugerido: `PATCH /admin/estacoes/:id` com `estacao[ultimo_contato]=<data futura ou manipulada>` e verificar que o valor é persistido sem nenhuma validação/rejeição.

### Bug 4 — `cod_ativacao` não é normalizado (strip), permitindo espaços invisíveis que quebram silenciosamente a validação

- Severidade: 🟡 Médio
- RF/RN violado: Task 1.4 (validação de `codAtivacao` do protocolo DES) — robustez contra dado malformado
- Passos:
  1. Um administrador cadastra uma estação pela UI com `cod_ativacao: "abc-123 "` (espaço à direita, ex: colado de outro lugar) — nem o form nem o model fazem `strip`.
  2. A estação física, ao enviar `codAtivacao=abc-123` (sem espaço) via `ValidarFrequentadorController`/`SincronizarRegistrosPontoController`/`AdicioneEstacaoController`, tem seu código comparado via `where("lower(cod_ativacao) = ?", codigo.downcase)` — comparação exata (menos o case), então `"abc-123 "` ≠ `"abc-123"`.
- Atual: A validação falha (`USUARIO_SENHA_INVALIDOS` / `"sincronizado"` sem persistir / heartbeat `"false"`) sem nenhuma mensagem diagnosticável — na tela admin o espaço é invisível, então o operador vê os dois valores como "idênticos" e não consegue entender por que a estação não autentica.
- Esperado: Normalizar `cod_ativacao` com `strip` tanto na gravação (model, via `before_validation`) quanto na comparação (`codigo_ativacao_valido?`/`registrar_contato`), ou ao menos validar formato (ex: `format: { with: /\A\S+\z/ }`) para rejeitar espaços na criação.
- Teste sugerido: `EstacaoPonto.create!(cod_ativacao: "abc-123 ", descricao: "X")` seguido de `EstacaoPonto.codigo_ativacao_valido?("abc-123")` → hoje retorna `false`.

### Bug 5 — Parâmetro `estadoEstacao` do heartbeat (EP-06) é ignorado, perdendo o sinal de saúde da estação

- Severidade: 🟢 Baixo
- RF/RN violado: Contrato documentado em `documentacao-estacao-ponto.md:1430-1440` (EP-06 `AdicioneEstacao` — campo `estadoEstacao` obrigatório, ex: `"FUNCIONANDO"`)
- Passos:
  1. A EstaçãoPonto desktop envia `GET /presenca/AdicioneEstacao?codAtivacao=X&versao=1.2&estadoEstacao=FUNCIONANDO` (ou outro valor de estado, se existir) a cada 5 minutos.
  2. `Presenca::AdicioneEstacaoController#show` lê apenas `codAtivacao` e `versao` — `params[:estadoEstacao]` nunca é consultado nem persistido.
- Atual: O sistema não tem como diferenciar uma estação "FUNCIONANDO" de uma em estado degradado/erro (se o client algum dia reportar um valor diferente) — toda informação de `estadoEstacao` é descartada silenciosamente.
- Esperado: Ao menos logar ou persistir `estadoEstacao` (ex: novo campo ou log estruturado) para uso futuro de monitoramento, já que o próprio protocolo documentado prevê o campo como obrigatório.
- Teste sugerido: Enviar `estadoEstacao=ERRO` (ou qualquer valor) no heartbeat e confirmar que nada no sistema registra essa informação (nem log, nem coluna).

## Cenários Testados (sem bugs)

- `require_admin` bloqueia corretamente `new/create/edit/update/destroy` para usuário não-admin (redirect com alert), enquanto `index` continua acessível — confirma a correção do blocker anterior de broken access control.
- Migração de dados `SeedEstacaoPontoLegado` recria corretamente `poc-ativacao-001` via `find_or_create_by!`, idempotente em re-run.
- `codigo_ativacao_valido?` trata corretamente `nil`/`""` (blank) retornando `false` sem lançar exceção.
- Sentinela `SistemaOperacionalNaoSuportado` continua sempre válido em `codigo_ativacao_valido?` e corretamente ignorado (retorna `nil`, não persiste) em `registrar_contato` — preserva o comportamento legado exigido pelo ADR-0003.
- `registrar_contato` para `cod_ativacao` inexistente retorna `nil` sem lançar exceção (heartbeat de estação nunca cadastrada é tratado graciosamente, resposta `"false"` em texto puro — sem mudança de contrato/HTTP status).
- Formato de resposta do protocolo `presenca/*` (texto puro `"true"/"false"` em EP-06, `"USUARIO_SENHA_INVALIDOS"`/id em `ValidarFrequentador`, `"sincronizado"` em `SincronizarRegistrosPonto` sem `confirmacaoVisual`) confere com o contrato documentado em `documentacao-estacao-ponto.md` — sem regressão observável de protocolo.
- `SincronizarRegistrosPontoController` mantém o comportamento pré-R.6 (200/"sincronizado" mesmo com rejeições) quando não há sinalização de formato rico — preservado.
- Form admin (`_form.html.erb`) exibe corretamente erros de validação (`@estacao.errors.full_messages`) para campos ausentes (`descricao`, `cod_ativacao` em branco).
- CRUD completo (create/edit/update/destroy) funciona para o fluxo feliz com dados válidos.
- Tela `index` trata corretamente base vazia ("Nenhuma estação cadastrada").
- `estacao_params` usa strong parameters — não há mass assignment de campos fora da whitelist.
- Injeção SQL: `where("lower(cod_ativacao) = ?", ...)` é parametrizada corretamente, sem risco de SQL injection mesmo com `codAtivacao` contendo aspas/caracteres especiais.
- `destroy` de estação inexistente (`id` inválido) resulta em `ActiveRecord::RecordNotFound` tratado pelo comportamento padrão do Rails (404), sem vazar stacktrace em produção.
- Migration reversível (`down` remove o registro seed) funciona corretamente.

## Veredito Final

Nenhum blocker de segurança/regressão de protocolo foi encontrado desta vez (os dois blockers anteriores — broken access control e regressão de `codAtivacao` legado — seguem corrigidos). O achado mais sério agora é de **integridade de dado sob concorrência** (Bug 1): a garantia de unicidade case-insensitive de `cod_ativacao`, que é a âncora de todo o protocolo `presenca/*` reformulado nesta sprint, não está reforçada no banco — apenas no nível da aplicação, com uma janela de corrida real. Como o Bug 2 (falta de índice funcional) tem a mesma causa raiz e a mesma correção (índice único funcional sobre `lower(cod_ativacao)`), recomendo tratá-los juntos antes do merge. Bugs 3 e 4 são de integridade/UX e podem ser corrigidos em iteração subsequente sem bloquear o merge, desde que documentados. Bug 5 é informativo, para backlog.

**Prioridade sugerida de correção:** Bug 1 + Bug 2 (mesma causa raiz, ambos antes do deploy) → Bug 4 → Bug 3 → Bug 5.
