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
      @media_directory = params[:files_directory] || './tdlib_files'
      @auth_ready = false
      @by_qr = params[:by_qr] || false

      setup_directories

      @client = TD::Client.new(database_directory: params[:database_directory] || './tdlib_database',
                               files_directory: @media_directory)

      setup_handlers
    end

    def run
      return unless connect

      puts '➡️ [CLIENT] Waiting for authorization...'

      while @client.alive? && !@auth_ready
        process_auth_state(by_qr: @by_qr)
        sleep 0.1
      end


      if @auth_ready
        puts "\n   ✅ Authorized..."

        subscribe_channel_posts(@client)

        shutdown = false
        Signal.trap('INT')  { shutdown = true } # CTRL-C
        Signal.trap('TERM') { shutdown = true }

        puts '➡️ [CLIENT] Main loop is working CTRL-C to stop .'

        sleep 1 while @client.alive? && !shutdown
      end

      close
    end
  end
end

# https://core.telegram.org/tdlib/docs/classtd_1_1td__api_1_1_function.html
