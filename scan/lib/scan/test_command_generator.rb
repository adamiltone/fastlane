module Scan
  # Responsible for building the fully working xcodebuild command
  class TestCommandGenerator
    class << self
      def generate
        parts = prefix
        parts << "env NSUnbufferedIO=YES xcodebuild"
        parts += options
        parts += actions
        parts += suffix
        parts += pipe

        parts
      end

      def prefix
        ["set -o pipefail &&"]
      end

      # Path to the project or workspace as parameter
      # This will also include the scheme (if given)
      # @return [Array] The array with all the components to join
      def project_path_array
        proj = Scan.project.xcodebuild_parameters
        return proj if proj.count > 0
        UI.user_error!("No project/workspace found")
      end

      def options
        config = Scan.config

        options = []
        options += project_path_array unless config[:xctestrun]
        options << "-sdk '#{config[:sdk]}'" if config[:sdk]
        options << destination # generated in `detect_values`
        options << "-derivedDataPath '#{config[:derived_data_path]}'" if config[:derived_data_path]
        options << "-resultBundlePath '#{result_bundle_path}'" if config[:result_bundle]
        options << "-enableCodeCoverage #{config[:code_coverage] ? 'YES' : 'NO'}" unless config[:code_coverage].nil?
        options << "-enableAddressSanitizer #{config[:address_sanitizer] ? 'YES' : 'NO'}" unless config[:address_sanitizer].nil?
        options << "-enableThreadSanitizer #{config[:thread_sanitizer] ? 'YES' : 'NO'}" unless config[:thread_sanitizer].nil?
        options << "-xcconfig '#{config[:xcconfig]}'" if config[:xcconfig]
        options << "-xctestrun '#{config[:xctestrun]}'" if config[:xctestrun]
        options << config[:xcargs] if config[:xcargs]

        # detect_values will ensure that these values are present as Arrays if
        # they are present at all
        options += config[:only_testing].map { |test_id| "-only-testing:#{test_id}" } if config[:only_testing]
        options += config[:skip_testing].map { |test_id| "-skip-testing:#{test_id}" } if config[:skip_testing]

        options
      end

      def actions
        config = Scan.config

        actions = []
        actions << :clean if config[:clean]

        if config[:build_for_testing]
          actions << "build-for-testing"
        elsif config[:test_without_building] || config[:xctestrun]
          actions << "test-without-building"
        else
          actions << :build unless config[:skip_build]
          actions << :test
        end

        actions
      end

      def suffix
        suffix = []
        suffix
      end

      def pipe
        # During building we just show the output in the terminal
        # Check out the ReportCollector class for more xcpretty things
        pipe = ["| tee '#{xcodebuild_log_path}'"]

        if Scan.config[:output_style] == 'raw'
          return pipe
        end

        formatter = []
        if Scan.config[:formatter]
          formatter << "-f `#{Scan.config[:formatter]}`"
        elsif FastlaneCore::Env.truthy?("TRAVIS")
          formatter << "-f `xcpretty-travis-formatter`"
          UI.success("Automatically switched to Travis formatter")
        end

        if Helper.colors_disabled?
          formatter << "--no-color"
        end

        if Scan.config[:output_style] == 'basic'
          formatter << "--no-utf"
        end

        if Scan.config[:output_style] == 'rspec'
          formatter << "--test"
        end

        return pipe << ["| xcpretty #{formatter.join(' ')}"]
      end

      # Store the raw file
      def xcodebuild_log_path
        file_name = "#{Scan.project.app_name}-#{Scan.config[:scheme]}.log"
        containing = File.expand_path(Scan.config[:buildlog_path])
        FileUtils.mkdir_p(containing)

        return File.join(containing, file_name)
      end

      # Generate destination parameters
      def destination
        unless Scan.cache[:destination]
          Scan.cache[:destination] = [*Scan.config[:destination]].map { |dst| "-destination '#{dst}'" }.join(' ')
        end
        Scan.cache[:destination]
      end

      # The path to set the Derived Data to
      def build_path
        unless Scan.cache[:build_path]
          day = Time.now.strftime("%F") # e.g. 2015-08-07

          Scan.cache[:build_path] = File.expand_path("~/Library/Developer/Xcode/Archives/#{day}/")
          FileUtils.mkdir_p Scan.cache[:build_path]
        end
        Scan.cache[:build_path]
      end

      def result_bundle_path
        unless Scan.cache[:result_bundle_path]
          Scan.cache[:result_bundle_path] = File.join(Scan.config[:output_directory], Scan.config[:scheme]) + ".test_result"
        end
        return Scan.cache[:result_bundle_path]
      end
    end
  end
end
