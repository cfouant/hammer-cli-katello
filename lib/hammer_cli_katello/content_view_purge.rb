module HammerCLIKatello
  class ContentViewPurgeCommand < HammerCLIKatello::Command
    include HammerCLIForemanTasks::Async
    include HammerCLIKatello::ApipieHelper
    include OrganizationOptions

    command_name "purge"
    desc "Delete old versions of a content view"

    option "--id", "ID", _("Content View numeric identifier")
    option "--name", "NAME", _("Content View name")
    option "--count", "COUNT", _("count of unused versions to keep"),
           default: 3, format: HammerCLI::Options::Normalizers::Number.new

    validate_options do
      organization_options = [:option_organization_id, :option_organization_name, \
                              :option_organization_label]

      any(:option_name, :option_id).required

      if option(:option_name).exist?
        any(*organization_options).required
      end
    end

    build_options

    class ContentViewIdParamSource
      def initialize(command)
        @command = command
      end

      def get_options(_defined_options, result)
        if result['option_id'].nil? && result['option_name']
          result['option_id'] = @command.resolver.content_view_id(result)
        end
        result
      end
    end

    def option_sources
      sources = super
      idx = sources.index { |s| s.class == HammerCLIForeman::OptionSources::IdParams }
      sources.insert(idx, ContentViewIdParamSource.new(self))
      sources
    end

    def execute
      if option_count.negative?
        output.print_error _("Invalid value for --count option: value must be 0 or greater.")
        return HammerCLI::EX_USAGE
      end

      # Check if there is something to do
      if option_count >= old_unused_versions.size
        output.print_error _("No versions to delete.")
        HammerCLI::EX_NOT_FOUND
      else
        versions_to_purge = old_unused_versions.slice(0, old_unused_versions.size - option_count)

        versions_to_purge.each do |v|
          purge_version(v)
        end
        HammerCLI::EX_OK
      end
    end

    private def purge_version(v)
      if option_async?
        task = destroy(:content_view_versions, 'id' => v["id"])
        print_message _("Version '%{version}' of content view '%{view}' scheduled "\
                        "for deletion in task '%{task_id}'.") %
                      {version: v["version"], view: v["content_view"]["name"], task_id: task['id']}
      else
        task_progress(call(:destroy, :content_view_versions, 'id' => v["id"]))
        print_message _("Version '%{version}' of content view '%{view}' deleted.") %
                      {version: v["version"], view: v["content_view"]["name"]}
      end
    end

    private def old_unused_versions
      return @old_unused_versions if @old_unused_versions

      all_versions = index(:content_view_versions, :content_view_id => options['option_id'])
      all_versions.sort_by! { |v| [v['major'], v['minor']] }
      @old_unused_versions = all_versions.select do |v|
        v["environments"].empty? &&
          v["composite_content_views"].empty? &&
          v["composite_content_view_versions"].empty?
      end
    end
  end
end
