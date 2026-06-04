module TD
  module Extension
    module MediaLoader
      # Works only after we fetch this message
      def download_file(file_id, dest_dir: @media_directory, timeout: 60)
        file = load_downloaded_file(file_id, timeout:)

        process_local_file(file.local.path, dest_dir) if file_downloaded?(file)
      rescue StandardError => e
        puts "❌ download_file error: #{e.message}"

        nil
      end

      def file_downloaded?(file)
        file.is_a?(TD::Types::File) && file.local&.is_downloading_completed
      end

      def load_downloaded_file(file_id, timeout: 60)
        @client.download_file(file_id: file_id, priority: 1, offset: 0, limit: 0,
                              synchronous: true).value!(timeout)
      rescue StandardError => e
        puts "⚠️ load_downloaded_file error: #{e.message}"
        nil
      end

      def process_local_file(src, dest_dir)
        return if src.to_s.empty? || !File.exist?(src)

        if File.extname(dest_dir) && !File.extname(dest_dir).empty?
          dst = dest_dir
          FileUtils.mkdir_p(File.dirname(dst))
        else
          FileUtils.mkdir_p(dest_dir)
          dst = File.join(dest_dir, File.basename(src))
        end

        begin
          FileUtils.mv(src, dst)
        rescue StandardError
          FileUtils.cp(src, dst)
        end

        begin
          File.chmod(0o666, dst)
        rescue StandardError => e
          puts "⚠️ Could not change file rights: #{e.message}"
        end

        dst
      end
    end
  end
end
