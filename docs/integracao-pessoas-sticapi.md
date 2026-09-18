# Integração com o Sistema Pessoas (Sticapi)

> Referência técnica da Sprint 8 (`SPRINT-PLAN.md`). Descreve o campo de vínculo, o fluxo de espelhamento de dados e como estender a integração em sprints futuras.

## Campo de vínculo: `users.cpf`

Chave usada para relacionar um `User` (Frequentador) local do Frequencia ao registro correspondente no sistema Pessoas.

- Coluna `string`, nullable, índice único (`db/migrate/20260828130834_add_cpf_to_users.rb`)
- Nullable porque frequentadores cadastrados manualmente (sem vínculo com o Pessoas) continuam funcionando normalmente — o CPF é preenchido quando o vínculo é estabelecido, não é obrigatório no cadastro
- Validado em `app/models/user.rb`: formato de 11 dígitos, único quando presente, sem exigir presença (`allow_nil: true`)

## Fluxo de espelhamento

Os dados cadastrais do Frequentador não são consultados ao vivo na Sticapi durante o request — são espelhados localmente por um job, seguindo o mesmo padrão usado no Pessoas2 (`ImportarUnidadesJob`/`unidades_controller.rb`).

```
SticapiClient::Pessoas.get_by_cpf(cpf: user.cpf)
        ↓
app/jobs/importar_dados_pessoa_job.rb
        ↓
  upsert nos campos espelhados do User (hoje: nome_completo)
```

### Gatilho automático

`config/recurring.yml` (Solid Queue), ambiente `production`:

```yaml
importar_dados_pessoa:
  class: ImportarDadosPessoaJob
  queue: default
  schedule: at midnight every day
```

Roda uma vez por dia, à meia-noite, varrendo todos os `User` com `cpf` preenchido (`ImportarDadosPessoaJob.perform_later` sem argumento).

### Gatilho manual

Botão "Reimportar do Pessoas" em `admin/frequentadores/index` (visível só quando o frequentador tem `cpf` cadastrado) → `Admin::FrequentadoresController#reimportar_dados_pessoa` → `ImportarDadosPessoaJob.perform_later(user.id)`.

### Lock de concorrência

Sem Redis disponível (o projeto usa Solid Queue, não Sidekiq), o lock usa **advisory lock do Postgres** (`pg_try_advisory_lock`/`pg_advisory_unlock`), com uma chave fixa (`ImportarDadosPessoaJob::LOCK_KEY`). Garante que duas execuções do job (automática + manual, ou duas manuais em sequência) não rodem em paralelo. A chave é um inteiro fixo, não `String#hash` — que é randomizado por processo no Ruby e não serviria como chave estável entre workers.

### Credenciais

`config/sticapi.yml` lê a credencial da Sticapi de `Rails.application.credentials.sticapi` (Rails encrypted credentials, `config/credentials.yml.enc` + `config/master.key`), com fallback para variáveis de ambiente (`STICAPI_HOST`, `STICAPI_USER`, `STICAPI_PASSWORD`, etc.) — úteis para sobrescrever em CI/deploy sem tocar nas credentials.

**Atenção:** a gem `sticapi_client` (>= 4.x) lê `ENV["STICAPI_HOST"]` diretamente dentro de si mesma — se essa variável estiver setada no processo, a gem ignora `config/sticapi.yml` por completo (não passa nem pelo fallback de credentials). Isso é comportamento da gem, não deste projeto.

A credencial atual é a mesma já usada pelo Pessoas2 (usuário `pessoas@sticapps.tjpi`), reaproveitada por decisão do usuário. Risco registrado: a mesma senha agora existe em dois repositórios — considerar credencial dedicada (`frequencia@sticapps.tjpi` ou similar) no futuro.

## Escopo atual (Sprint 8) vs. futuro

A Sprint 8 entrega **só a fundação**: autenticação funcionando, campo `cpf`, job com os dois gatilhos, e espelhamento de **um único campo** (`nome_completo`), para provar o fluxo ponta a ponta.

Deliberadamente fora de escopo, para sprints futuras (Parte 2, Sprint 10 em diante — `SPRINT-PLAN.md`):
- Campos adicionais do Pessoas (órgão, vínculo, situação funcional, lotação)
- Tabela de espelho dedicada (`FrequentadorCache`) para dados que não fazem sentido morar direto em `users`
- Sincronização em lote (hoje o gatilho manual reimporta um frequentador por vez)

## Como adicionar um novo campo espelhado

1. Confirmar o endpoint/campo correspondente no módulo `SticapiClient::Pessoas` (ver gem `sticapi_client`, `lib/sticapi_client/pessoas.rb`)
2. Se o campo for do próprio `User` (ex.: outro dado cadastral direto), adicionar ao `update!` em `ImportarDadosPessoaJob#importar_usuario`
3. Se o campo pertencer a uma entidade separada (ex.: órgão, vínculo — que têm suas próprias tabelas no Pessoas), avaliar se precisa de uma tabela de espelho própria (`FrequentadorCache`) em vez de crescer `users` indefinidamente — ver Sprint 10
4. Adicionar teste unitário no job (mock de `SticapiClient::Pessoas`, sem chamada HTTP real — ver `test/jobs/importar_dados_pessoa_job_test.rb`)
5. Atualizar este documento e a task correspondente em `SPRINT-PLAN.md`

## Referências

- `SPRINT-PLAN.md`, Sprint 8 (fundação) e Sprint 10 (extensão — grid de frequentadores)
- `app/jobs/importar_dados_pessoa_job.rb`
- `app/controllers/admin/frequentadores_controller.rb`
- `config/sticapi.yml`, `config/recurring.yml`
- Padrão de referência no Pessoas2: `app/jobs/importar_unidades_job.rb`, `app/controllers/unidades_controller.rb`
