# encoding: utf-8
# author: Dominik Richter
# author: Christoph Hartmann

require 'rspec/core'
require 'rspec/its'
require 'inspec/rspec_json_formatter'

# There be dragons!! Or borgs, or something...
# This file and all its contents cannot be unit-tested. both test-suits
# collide and disable all unit tests that have been added.

module Inspec
  class RunnerRspec # rubocop:disable Metrics/ClassLength
    def initialize(conf)
      @conf = conf
      @formatter = nil
      reset
    end

    # Create a new RSpec example group from arguments and block.
    #
    # @param [Type] *args list of arguments for this example
    # @param [Type] &block the block associated with this example group
    # @return [RSpecExampleGroup]
    def example_group(*args, &block)
      RSpec::Core::ExampleGroup.describe(*args, &block)
    end

    # Add a full profile to the runner. Only pulls in metadata
    #
    # @param [Inspec::Profile] profile
    # @return [nil]
    def add_profile(profile)
      RSpec.configuration.formatters
           .find_all { |c| c.is_a? InspecRspecJson }
           .each do |fmt|
        fmt.add_profile(profile)
      end
    end

    # Configure the backend of the runner.
    #
    # @param [Inspec::Backend] backend
    # @return [nil]
    def backend=(backend)
      RSpec.configuration.formatters
           .find_all { |c| c.is_a? InspecRspecJson }
           .each do |fmt|
        fmt.backend = backend
      end
    end

    # Add an example group to the list of registered tests.
    #
    # @param [RSpecExampleGroup] example test
    # @param [String] rule_id the ID associated with this check
    # @return [nil]
    def add_test(example, rule)
      set_rspec_ids(example, rule)
      @tests.example_groups.push(example)
    end

    # Retrieve the list of tests that have been added.
    #
    # @return [Array] full list of tests
    def tests
      @tests.ordered_example_groups
    end

    # Run all registered tests with an optional test runner.
    #
    # @param [RSpecRunner] with is an optional RSpecRunner
    # @return [int] 0 if all went well; otherwise nonzero
    def run(with = nil)
      with ||= RSpec::Core::Runner.new(nil)
      with.run_specs(tests)
    end

    # Provide an output hash of the run's report
    #
    # @return [Hash] a run's output hash
    def report
      reporter = @formatter || RSpec.configuration.formatters[0]
      return nil if reporter.nil? || !reporter.respond_to?(:output_hash)
      reporter.output_hash
    end

    # Empty the list of registered tests.
    #
    # @return [nil]
    def reset
      @tests = RSpec::Core::World.new
      # resets "pending examples" in reporter
      RSpec.configuration.reset
      configure_output
    end

    #
    # Add an Inspec::Rule to the set of tests we are going to run.
    # First rules must be converted to Rspec::ExampleGroup's
    #
    # @params rule [Inspec::Rule]
    #
    def add_rule(rule)
      checks = ::Inspec::Rule.prepare_checks(rule)
      examples = checks.flat_map do |m, a, b|
        check_to_example(m, a, b)
      end.compact

      examples.each { |e| add_test(e, rule) }
    end

    private

    FORMATTERS = {
      'json-min' => 'InspecRspecMiniJson',
      'json' => 'InspecRspecJson',
      'json-rspec' => 'InspecRspecVanilla',
      'cli' => 'InspecRspecCli',
    }.freeze

    def block_source_info(block)
      return {} if block.nil? || !block.respond_to?(:source_location)
      opts = {}
      file_path, line = block.source_location
      opts['file_path'] = file_path
      opts['line_number'] = line
      opts
    end

    def check_to_example(method_name, arg, block)
      opts = block_source_info(block)

      skip_check = !arg.empty? && arg[0].respond_to?(:resource_skipped) && !arg[0].resource_skipped.nil?

      if skip_check
        example_group(*arg, opts) do
          it arg[0].resource_skipped
        end
      else
        case method_name
        when 'describe'
          example_group(*arg, opts, &block)
        when 'expect'
          block.example_group
        when 'describe.one'
          tests = arg.map do |x|
            example_group(x[1][0], block_source_info(x[2]), &x[2])
          end

          return nil if tests.empty?
          ok_tests = tests.find_all(&:run)

          # return all tests if none succeeds; we will just report full failure
          if ok_tests.empty?
            tests
          else
            ok_tests
          end
        else
          fail "A rule was registered with #{method_name.inspect}, "\
               "which isn't understood and cannot be processed."
        end
      end
    end

    # Configure the output formatter and stream to be used with RSpec.
    #
    # @return [nil]
    def configure_output
      if !@conf['output'] || @conf['output'] == '-'
        RSpec.configuration.output_stream = $stdout
      else
        RSpec.configuration.output_stream = @conf['output']
      end

      format = FORMATTERS[@conf['format']] || @conf['format'] || FORMATTERS['cli']
      @formatter = RSpec.configuration.add_formatter(format)
      RSpec.configuration.color = @conf['color']

      setup_reporting if @conf['report']
    end

    def setup_reporting
      RSpec.configuration.add_formatter(Inspec::RSpecReporter)
    end

    # Make sure that all RSpec example groups use the provided ID.
    # At the time of creation, we didn't yet have full ID support in RSpec,
    # which is why they were added to metadata directly. This is evaluated
    # by the InSpec adjusted json formatter (rspec_json_formatter).
    #
    # @param [RSpecExampleGroup] example object which contains a check
    # @return [Type] description of returned object
    def set_rspec_ids(example, rule)
      assign_rspec_ids(example.metadata, rule)
      example.filtered_examples.each do |e|
        assign_rspec_ids(e.metadata, rule)
      end
      example.children.each do |child|
        set_rspec_ids(child, rule)
      end
    end

    def assign_rspec_ids(metadata, rule)
      metadata[:id] = ::Inspec::Rule.rule_id(rule)
      metadata[:profile_id] = ::Inspec::Rule.profile_id(rule)
      metadata[:impact] = rule.impact
      metadata[:title] = rule.title
      metadata[:desc] = rule.desc
      metadata[:code] = rule.instance_variable_get(:@__code)
      metadata[:source_location] = rule.instance_variable_get(:@__source_location)
    end
  end

  class RSpecReporter < RSpec::Core::Formatters::JsonFormatter
    RSpec::Core::Formatters.register Inspec::RSpecReporter

    def initialize(*)
      super(StringIO.new)
    end
  end
end
