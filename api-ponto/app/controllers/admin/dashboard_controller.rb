module Admin
  class DashboardController < Admin::ApplicationController
    def index
      # Task 23.7 — CanCanCan: autorização explícita para leitura do dashboard.
      # Admin, gestor e operador podem visualizar (todos têm :read em :all).
      authorize! :read, :all

      if current_user.admin?
        hoje = Time.current.beginning_of_day

        @total_usuarios = User.count
        @usuarios_ativos = User.ativos.count
        @usuarios_inativos = @total_usuarios - @usuarios_ativos
        @usuarios_com_digitais = User.com_digitais.count

        @registros_hoje = TimeRecord.where("punched_at >= ?", hoje).count
        @registros_semana = TimeRecord.where("punched_at >= ?", 7.days.ago).count
        @registros_mes = TimeRecord.where("punched_at >= ?", 30.days.ago).count

        # Sprint 15 (task 15.1): KPIs simples de "Fase A" — contagem direta,
        # sem nenhum cálculo de banco de horas/fechamento (Fase B, Sprint
        # 16+, ver task 15.2). `EstacaoPonto` não tem campo de
        # status/ativação no schema atual (não existe coluna `ativa` nem
        # conceito de desativação) — toda estação cadastrada é contada, já
        # que o schema não distingue estações ativas de inativas nesta fase.
        #
        # `@total_frequentadores` trocado de `FrequentadorCache.count`
        # (espelho local) para SELECT ao vivo no pessoas2 (pedido do
        # usuário, 2026-09-02) — mesma fonte já usada em
        # admin/frequentadores (task 10.10): todo vínculo ativo real.
        @total_frequentadores = Pessoas::Vinculo.ativos.count
        @total_estacoes = EstacaoPonto.count

        # Task 17.3 — 1o KPI real baseado em dado calculado (Fase B, Sprint
        # 17): total de faltas do mês corrente, somado de
        # `RegistroMensalFrequencia#faltas` (consolidação mensal,
        # `ConsolidacaoMensalService.consolidar`). Sem registro consolidado
        # pra nenhum usuário no mês ainda (ninguém rodou o cálculo), fica
        # `0` — mesma soma de coluna ausente que `.sum` já devolve, não
        # precisa de tratamento especial de "sem dado" como as telas de
        # tabela (não há "—" possível num KPI agregado por soma).
        @faltas_mes = RegistroMensalFrequencia.where(ano: hoje.year, mes: hoje.month).sum(:faltas)

        # "Últimas Batidas" exibe entradas e saídas em colunas separadas
        # (esquerda/direita) — buscamos os dois tipos independentemente para
        # que ambos os lados fiquem preenchidos mesmo se um tipo for muito
        # mais frequente que o outro no momento.
        @ultimas_entradas = TimeRecord.includes(:user)
                                       .where(punch_type: "entry")
                                       .order(created_at: :desc)
                                       .limit(5)
        @ultimas_saidas = TimeRecord.includes(:user)
                                     .where(punch_type: "exit")
                                     .order(created_at: :desc)
                                     .limit(5)
      end
    end
  end
end
