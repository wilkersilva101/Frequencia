# Espelha só as colunas da tabela `users` do banco do Pessoas que o
# Frequencia precisa pra autenticação (task 21.5, Sprint 21): `username`,
# `cpf` e `encrypted_password`. Não replica o model `User` inteiro do
# pessoas2 (que usa Devise com `:database_authenticatable`,
# `:rememberable`, `:trackable`, `:validatable`, `:recoverable`, roles
# etc.) — aqui só lemos o hash bcrypt já pronto pra validar localmente.
#
# Achado confirmado em `pessoas2/db/schema.rb`: `users.cpf` já existe
# direto na própria tabela `users` (não precisa de join com `pessoas`
# pra achar o CPF de quem está logando).
#
# Ver app/models/pessoas_record.rb: conexão somente-leitura, sem
# INSERT/UPDATE/DELETE em nenhuma camada.
module Pessoas
  class User < PessoasRecord
    self.table_name = "users"

    # Ponto de entrada único usado pelo fluxo de autenticação
    # (`app/models/user.rb#authenticate`). Isolado num método de classe
    # pra poder ser stubado nos testes — o banco `pessoas_test` não tem
    # schema carregado (mesma limitação documentada em
    # test/jobs/importar_dados_pessoa_job_test.rb e outros).
    def self.buscar_por_cpf(cpf)
      find_by(cpf: cpf)
    end
  end
end
