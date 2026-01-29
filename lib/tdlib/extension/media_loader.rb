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
        return nil if src.blank? || !File.exist?(src)

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

      # Uploads a local file to TDLib and returns the remote file id (integer) or nil on error.
      # Usage: upload_file('/path/to/file.jpg', timeout: 60)
      # ruby
      # Returns TDLib file id (integer) or nil.
      def preliminary_upload_file(path, type: :photo, priority: 1, timeout: 60)
        file_type = case type
                    when :photo       then { '@type' => 'fileTypePhoto' }
                    when :video       then { '@type' => 'fileTypeVideo' }
                    when :video_note  then { '@type' => 'fileTypeVideoNote' }
                    when :voice_note  then { '@type' => 'fileTypeVoiceNote' }
                    else { '@type' => 'fileTypeDocument' }
                    end

        req_args = { file: { '@type' => 'inputFileLocal', 'path' => path }, file_type:, priority: }
        file = @client.preliminary_upload_file(**req_args).value!(timeout)

        HashHelper.get_unknown_structure_data(file, 'id')
      rescue TD::Error => e
        warn "preliminary_upload_file failed: #{e.message}"
        nil
      rescue StandardError => e
        warn "preliminary_upload_file error: #{e.message}"
        nil
      end

      def wait_for_upload(file_id, timeout: 60, interval: 1)
        deadline = Time.now + timeout

        loop do
          f = begin
            @client.get_file(file_id: file_id).value!(5)
          rescue StandardError => _e
            nil
          end

          if f&.remote
            uploaded = HashHelper.get_unknown_structure_data(f.remote, 'uploaded_size')
            expected = HashHelper.get_unknown_structure_data(f, 'expected_size')
            remote_id = HashHelper.get_unknown_structure_data(f.remote, 'id')
            unique_id = HashHelper.get_unknown_structure_data(f.remote, 'unique_id')
            completed_flag = HashHelper.get_unknown_structure_data(f.remote, 'is_uploading_completed')

            if completed_flag || (unique_id && !unique_id.to_s.empty?) ||
               (uploaded && expected && uploaded >= expected) ||
               (remote_id && !remote_id.to_s.empty?)

              puts '✅ Upload completed'

              return true
            end
          end

          return false if Time.now >= deadline

          sleep interval
        end
      end
    end
  end
end
