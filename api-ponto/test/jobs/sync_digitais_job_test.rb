require "test_helper"

class SyncDigitaisJobTest < ActiveJob::TestCase
  test "delega o trabalho para o Intranet::SyncDigitaisService e loga o resumo" do
    chamou = false
    log = StringIO.new

    # Substitui o método de classe do serviço, sem tocar no MySQL real.
    original_call = Intranet::SyncDigitaisService.method(:call)
    Intranet::SyncDigitaisService.define_singleton_method(:call) do |*_args|
      chamou = true
      { atualizados: 3, sem_alteracao: 2, ignorados: 0, erros: 0, processados: 5 }
    end

    Rails.logger = Logger.new(log)
    SyncDigitaisJob.perform_now

    assert chamou, "esperava que o serviço fosse chamado"
    assert_match(/SyncDigitaisJob concluído/, log.string)
  ensure
    Rails.logger = Logger.new(IO::NULL)
    Intranet::SyncDigitaisService.singleton_class.send(:define_method, :call, original_call)
  end
end
