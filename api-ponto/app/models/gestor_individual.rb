class GestorIndividual < ApplicationRecord
  # Corresponde ao legado `presenca_gestorindividual` — no legado é uma
  # tabela de ligação (vinculado_id do gestor, no domínio de Pessoas, →
  # frequentador_id do gerido, local), com o gestor identificado por seu
  # vínculo em Pessoas, não necessariamente um login local da estação.
  #
  # Sticapi expõe o equivalente real via
  # `SticapiClient::Intranet.gestores_individuais` (campos: id,
  # data_criacao, data_exclusao, observacao, id_vinculo_gestor,
  # matricula_gestor, id_vinculo_gerido, matricula_gerido) — importar isso
  # exigiria resolução de matrícula→CPF (mesmo problema da Sprint 10B) e
  # fica para uma sprint futura. Por ora (Fase A, "popular o front"), é
  # cadastro local simples — mesmo espírito de `Regime`/`EstacaoPonto`
  # antes de qualquer importação real.
  #
  # `self.table_name` explícito: "gestor individual" pluraliza em
  # português como "gestores individuais" (as duas palavras concordam),
  # diferente do que o Rails infere automaticamente a partir do nome da
  # classe — mesmo caso do `EstacaoPonto`.
  self.table_name = "gestores_individuais"

  # `restrict_with_exception` (e NÃO `:destroy`) — Bug 2 do Bug Finder da 29.2:
  # com `dependent: :destroy`, um `destroy` no gestor apagava fisicamente as
  # linhas de vínculo em cascata, contornando por completo o soft-delete de
  # `Desativavel` e violando a regra "nunca hard-delete / preserve o histórico
  # operacional". Aqui `destroy` levanta se houver vínculos, em vez de apagá-los
  # em silêncio — mesmo padrão já usado em `User` e `Regime` para associações
  # históricas. Não há consumidor que dependa do cascade hoje (a tela só tem
  # `index`).
  #
  # Achado 12 do Code Reviewer (2026-09-29) — correção de comentário: o
  # `restrict_with_exception` levanta `DeleteRestrictionError` com mensagem
  # fixa em INGLÊS ("Cannot delete record because of dependent ..."), sem
  # passar por I18n (`activerecord-8.0.5/lib/active_record/associations/
  # errors.rb`). É `restrict_with_ERROR` que usa a chave
  # `restrict_dependent_destroy` — e ela não é usada em nenhum model do app.
  #
  # Achado 2 do Code Reviewer — `gerenciados` NÃO filtra por `ativos` e o
  # índice UNIQUE parcial torna esperado que o mesmo par exista mais de uma vez
  # (inativo antigo + ativo novo), então esta associação devolve o MESMO
  # usuário duplicado. Quem precisa da lista corrente deve usar
  # `GestorIndividualGerenciado.ativos.where(gestor_individual: ...)` (débito
  # da 29.4/29.6, junto do Bug 16); a associação fica como está nesta tarefa.
  has_many :gestor_individual_gerenciados, dependent: :restrict_with_exception
  has_many :gerenciados, through: :gestor_individual_gerenciados, source: :user

  # Login local do gestor, quando existir (Tarefa 29.2). Opcional: no legado o
  # gestor é identificado pelo vínculo em Pessoas (`gestor_cpf`), não
  # necessariamente por um login da estação — por isso a FK anula.
  belongs_to :gestor_user, class_name: "User", optional: true

  validates :nome, presence: true
  # `id_legado` é único quando presente (índice UNIQUE no banco; múltiplos
  # NULL são permitidos, então registros locais convivem). É a chave de upsert
  # da importação da 29.3.
  validates :id_legado, uniqueness: true, allow_nil: true

  # Bug 10 do Bug Finder da 29.2 (⚪) — decisão do dev em 2026-09-29: mesmo
  # formato de CPF dos demais models do projeto (`User`, `FrequentadorCache`:
  # `format: { with: /\A\d{11}\z/ }`), sem máscara. `gestor_cpf` é a ponte de
  # casamento com o vínculo de Pessoas na importação da 29.3 — sem formato
  # fixo, o mesmo CPF em duas máscaras conviveria como dois registros e o
  # upsert casaria errado. `allow_nil` porque o gestor cadastrado localmente
  # não tem CPF.
  validates :gestor_cpf, format: { with: /\A\d{11}\z/ }, allow_nil: true

  # Bug 15 do Bug Finder da 2ª rodada da 29.2 (decisão do dev em 2026-09-29) —
  # auto-gerência "tardia".
  #
  # A regra de auto-gerência já é barrada pelo lado do VÍNCULO
  # (`InvarianteAutoGerencia#auto_gerencia_nao_ativa`, via o host
  # `GestorIndividualGerenciado`), mas aquela validação roda no `save` do
  # vínculo. No fluxo natural de cadastro
  # (cria o gestor → vincula os geridos → só então associa o login local), ela
  # nunca é reexecutada: o gestor ganhava `gestor_user` apontando para alguém
  # que já era seu próprio gerido ativo, e a auto-gerência passava silenciosa
  # — o que na cascata da 29.4/29.5 seria auto-autorização.
  #
  # O invariante é guardado pelos DOIS lados porque pode ser violado a partir
  # de dois caminhos distintos: criar/alterar o vínculo, ou dar login ao
  # gestor. Um `CHECK` no banco cruzando as duas tabelas não é possível no
  # Postgres (o próprio comentário do vínculo registra isso).
  #
  # Bug 17 do Bug Finder da 3ª rodada (🟠) — REGRESSÃO corrigida aqui: sem o
  # `if:`, a validação rodava em TODO save, então um vínculo de auto-gerência
  # "tardia" já persistido (criado por upsert/`insert_all!`, o caminho
  # documentado da 29.3) tornava o gestor um registro **travado**: renomear,
  # alterar `orgao`/`observacao` e até `desativar!` (que usa `update!`)
  # levantavam `RecordInvalid`, deixando `ativo=true` para sempre e sem
  # caminho de recuperação pela aplicação. A validação só precisa rodar quando
  # o invariante pode MUDAR — registro novo, ou `gestor_user_id` alterado.
  # Renomear um gestor não cria nem desfaz auto-gerência, logo não deve
  # revalidar. Isso também elimina o custo de +1 SELECT por save: o `exists?`
  # agora só roda quando o login é (re)definido.
  #
  # A REGRA **e o gatilho** vivem no módulo `InvarianteAutoGerencia` (29.2-D7,
  # decisão do CTO): antes estavam **copiados** aqui e em
  # `GestorIndividualGerenciado`, e essa duplicação produziu os Bugs 12/17/18
  # (a mesma classe de bug em três rodadas seguidas). O módulo registra o
  # `validate` no `included do`; cada host declara só a janela.
  include InvarianteAutoGerencia

  # Tarefa 29.2 — soft-delete via concern `Desativavel` (scope `ativos` +
  # `desativar!`), compartilhado com `GestorIndividualGerenciado`. A UI não tem
  # ação de exclusão hoje; o `destroy` NÃO é sobrescrito (nada chama hoje e
  # alterar sua semântica seria surpresa para código futuro). O predicado
  # `ativo?` vem do próprio ActiveRecord (coluna booleana `ativo`).
  include Desativavel

  private

  # --- Ponto de extensão do `InvarianteAutoGerencia` (lado do GESTOR) -------

  # Revalidar só no evento que muda o invariante: registro novo, ou o LOGIN
  # sendo definido/alterado. Renomear um gestor não cria nem desfaz
  # auto-gerência, logo não deve revalidar — senão um registro já inconsistente
  # fica travado (Bug 17). Elimina também o `+1 SELECT` por save.
  def janela_de_revalidacao
    new_record? || will_save_change_to_gestor_user_id?
  end

  # Aqui os dados são de OUTRA tabela (`gestor_individual_gerenciados`), então
  # sobrescrevemos como o módulo descobre o conflito e qual atributo acusa.
  #
  # Há vínculo ATIVO deste gestor cujo gerido é o próprio `gestor_user`?
  # Só vínculos ATIVOS contam: um gerido já desativado não é gerenciado hoje,
  # então dar login a ele não cria auto-autorização corrente (decisão do
  # Bug 15, espelhada no índice parcial do banco).
  def host_tem_auto_gerencia_ativa?
    return false if gestor_user_id.blank?

    if persisted?
      # `exists?` evita carregar a associação inteira.
      gestor_individual_gerenciados.ativos.where(user_id: gestor_user_id).exists?
    else
      # Gestor novo: os vínculos ainda não estão no banco, então olhamos os
      # que estão em memória.
      gestor_individual_gerenciados.any? do |vinculo|
        vinculo.ativo? && vinculo.user_id == gestor_user_id
      end
    end
  end

  def host_erro_attribute
    :gestor_user_id
  end

  # Achado 14 do Code Reviewer — mensagens de invariante passam por I18n (a
  # task que introduziu o módulo também mexeu no `pt-BR.yml` por completude de
  # i18n; deixar hardcoded seria exceção não documentada).
  def host_erro_mensagem
    I18n.t("activerecord.errors.models.gestor_individual.auto_gerencia")
  end
end
