class ValorRetroativo < ApplicationRecord
  # Sprint 18 (task 18.3) — correção retroativa de folha (UC-07). Portado de
  # `ValorRetroativo.java` (bean) + `ValorRetroativoDao.java` (Intranet
  # legada). `belongs_to :user` sem `OneToOne` — ver comentário de topo da
  # migration `CreateValorRetroativos` pra decisão completa.
  belongs_to :user

  validates :ano, presence: true
  validates :mes, presence: true, inclusion: { in: 1..12 }
  validates :data_geracao, presence: true
  validates :numero_hora, presence: true

  # DUV-011 — o bug real do legado, em `calcularValorRetroativo`
  # (`RelatorioFrequenciaFinalServices.java`, linhas 128-149):
  #
  #   int cont = 0;
  #   for (ValorRetroativo valor : valores) {
  #       ...
  #       if (mesDoValor == mes) {
  #           cont=+valor.getNumeroHora();  // <-- BUG
  #       }
  #   }
  #   return cont;
  #
  # `cont=+valor.getNumeroHora()` é interpretado pelo Java como
  # `cont = (+valor.getNumeroHora())` — atribuição do valor unário positivo
  # — e não `cont += valor.getNumeroHora()` (soma acumulada). Resultado real
  # do legado: quando há 2+ `ValorRetroativo` pro mesmo frequentador/mês/ano,
  # só o ÚLTIMO valor do loop que bate o filtro de mês sobrevive; os
  # anteriores são descartados silenciosamente, sem erro nem log.
  #
  # Aqui a soma é feita com `Enumerable#sum`/`.sum` do ActiveRecord — que
  # soma corretamente por construção, sem a armadilha de sintaxe do Java.
  # Não replicado o filtro redundante `mesDoValor == mes` do loop legado: o
  # `ValorRetroativoDao#getByMesAno` legado já filtra por
  # `frequentador+mes+ano` na própria query, e aqui o `where(user:, ano:, mes:)`
  # já faz o mesmo — todo registro retornado já é do mês/ano certo.
  def self.soma_do_mes(user, ano, mes)
    where(user: user, ano: ano, mes: mes).sum(:numero_hora)
  end
end
