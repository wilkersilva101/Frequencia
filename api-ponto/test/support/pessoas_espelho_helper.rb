# frozen_string_literal: true

# Helpers de dados para os espelhos `Pessoas::*` contra o schema real de teste
# (ADR-0006, regra 4). Não usamos YAML em test/fixtures porque `fixtures :all`
# quebraria em qualquer máquina sem o schema carregado.
#
# Os inserts vão pela conexão `pessoas` via `insert_all` (o `readonly?` dos
# espelhos só bloqueia save/update/destroy de instâncias). Como o Rails abre
# transação em TODOS os pools de escrita no setup de testes transacionais,
# tudo o que estes helpers inserem é revertido ao fim de cada teste.
#
# Pré-requisito: `RAILS_ENV=test bin/rails test:pessoas_schema:load`.
module PessoasEspelhoHelper
  def criar_pessoa(nome: "Pessoa Teste", cpf: proximo_cpf_teste, **atributos)
    inserir_espelho(Pessoas::Pessoa, nome: nome, cpf: cpf, **atributos)
  end

  # `parent:` monta o `ancestry` no formato materialized path do Pessoas2
  # (ids da raiz até o pai, separados por "/").
  def criar_unidade(descricao: "Unidade Teste", parent: nil, **atributos)
    atributos[:ancestry] = ancestry_filha_de(parent) if parent && !atributos.key?(:ancestry)

    inserir_espelho(Pessoas::Unidade, descricao: descricao, **atributos)
  end

  # Árvore de 3 níveis usada nos testes de hierarquia (29.1/29.4/29.6).
  def criar_arvore_unidades
    raiz = criar_unidade(descricao: "Raiz", active: true)
    intermediaria = criar_unidade(descricao: "Intermediária", parent: raiz, active: true)
    folha = criar_unidade(descricao: "Folha", parent: intermediaria, active: true)

    { raiz: raiz, intermediaria: intermediaria, folha: folha }
  end

  def criar_vinculo_estado(nome: "em_exercicio")
    Pessoas::VinculoEstado.find_by(nome: nome) || inserir_espelho(Pessoas::VinculoEstado, nome: nome)
  end

  # Pessoa com vínculo e lotação na unidade. Por padrão o vínculo está
  # `em_exercicio` e a lotação é principal e vigente (sem fim).
  def criar_pessoa_lotada(unidade:, nome: "Servidor Teste", cpf: proximo_cpf_teste, matricula: nil,
                          estado: "em_exercicio", principal: true, inicio: Date.new(2020, 1, 1), fim: nil)
    pessoa = criar_pessoa(nome: nome, cpf: cpf)
    vinculo = inserir_espelho(
      Pessoas::Vinculo,
      pessoa_id: pessoa.id,
      vinculo_estado_id: criar_vinculo_estado(nome: estado).id,
      matricula: matricula || "M#{pessoa.id}",
      inicio: inicio
    )
    inserir_espelho(
      Pessoas::Lotacao,
      vinculo_id: vinculo.id, unidade_id: unidade.id, principal: principal, inicio: inicio, fim: fim
    )

    pessoa
  end

  # Débito B1 do review final da 29.2 (2026-09-29) — guarda defensiva para
  # máquina/CI limpos.
  #
  # Os testes do espelho APENAS FUNCIONAM com o schema carregado
  # (`RAILS_ENV=test bin/rails test:pessoas_schema:load`, ver README). Em CI
  # limpo — ou numa máquina nova — as tabelas não existem e os testes
  # explodiam com `PG::UndefinedTable` em vez de falhar de forma
  # compreensível. Chamar isto no `setup` faz o teste ser PULADO com motivo
  # explícito, em vez de derrubar a suíte.
  #
  # Não substitui o CI correto (que deve preparar o banco — ver o passo no
  # `.github/workflows/ci.yml`): é a rede de segurança para quem roda a suíte
  # sem o setup, e mantém o sinal honesto de cobertura (um `skip` aparece no
  # relatório; um erro de conexão esconde o problema).
  def skip_sem_espelho!
    return if espelho_disponivel?

    skip "espelho Pessoas indisponível — rode `RAILS_ENV=test bin/rails test:pessoas_schema:load` (ver README)"
  end

  # A conexão `pessoas` está configurada e as tabelas do espelho existem?
  # Rescata falha de conexão (CI sem o banco) como "indisponível", não como erro.
  def espelho_disponivel?
    Pessoas::Unidade.connection.table_exists?(:pessoas)
  rescue ActiveRecord::ActiveRecordError, PG::Error
    false
  end

  private

  def inserir_espelho(model, **atributos)
    id = model.insert_all([ atributos ], returning: :id).rows.first.first
    model.find(id)
  end

  def ancestry_filha_de(parent)
    [ parent.ancestry.presence, parent.id ].compact.join("/")
  end

  # CPFs únicos por processo (o índice `index_pessoas_on_cpf` é unique); o
  # pid evita colisão visível entre workers enquanto as transações estão
  # abertas.
  def proximo_cpf_teste
    PessoasEspelhoHelper.proximo_cpf
  end

  def self.proximo_cpf
    @sequencia_cpf = @sequencia_cpf.to_i + 1
    format("9%05d%05d", Process.pid % 100_000, @sequencia_cpf)
  end
end
