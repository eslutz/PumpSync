#!/usr/bin/env ruby
# Check embedded shell blocks; valid YAML alone does not establish shell syntax.
require "yaml"
require "tempfile"

repository_root = File.expand_path("../..", __dir__)
workflow = YAML.load_file(File.join(repository_root, ".github/workflows/ios-ci.yml"))
workflow.fetch("jobs").each do |job_name, job|
  job.fetch("steps").each do |step|
    next unless step["run"]

    Tempfile.create(["pumpsync-ci-", ".sh"]) do |file|
      file.write(step.fetch("run"))
      file.flush
      unless system("bash", "-n", file.path)
        abort "Invalid shell syntax: #{job_name} / #{step.fetch('name', 'unnamed step')}"
      end
    end
  end
end
puts "All GitHub CI shell steps passed syntax validation."
