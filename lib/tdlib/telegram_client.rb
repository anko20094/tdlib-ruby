require 'fileutils'

module TD
  class TelegramClient
    include TD::Extension::ApiMethods
    include TD::Extension::MediaLoader
    include TD::Extension::Connection
    prepend TD::Extension::CustomUpdateHandler

    attr_reader :auth_ready, :client, :phone, :media_directory

    def initialize(params)
      @client = nil
      @auth_state = :initializing
      @phone = params[:phone] || ''
      @media_directory = params[:files_directory] || './tdlib_media'
      @auth_ready = false

      setup_directories

      @client = TD::Client.new(database_directory: params[:database_directory] || './tdlib_database',
                               files_directory: params[:files_directory] || './tdlib_files')

      setup_handlers
    end

    def run
      return unless connect

      puts '➡️ [CLIENT] Успішно підключено. Очікуємо авторизації...'

      while @client.alive? && !@auth_ready
        process_auth_state
        sleep 0.1
      end


      if @auth_ready
        puts "\n   ✅ Вхід успішний. Підписка на апдейти та перехід в головний цикл..."

        subscribe_channel_posts(@client)

        shutdown = false
        Signal.trap('INT')  { shutdown = true } # CTRL-C
        Signal.trap('TERM') { shutdown = true }

        puts '➡️ [CLIENT] Основний цикл працює. Натисніть CTRL-C щоб завершити.'

        sleep 1 while @client.alive? && !shutdown
      end

      close
    end
  end
end

# https://core.telegram.org/tdlib/docs/classtd_1_1td__api_1_1_function.html
