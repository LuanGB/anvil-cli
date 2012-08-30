require "anvil"
require "anvil/builder"
require "anvil/manifest"
require "anvil/version"
require "progress"
require "thor"
require "thread"
require "uri"

class Anvil::Engine < Thor

  def self.build(source, options={})
    if options[:pipeline]
      old_stdout = $stdout.dup
      $stdout = $stderr
    end

    source ||= "."

    build_options = {
      :buildpack => prepare_buildpack(options[:buildpack].to_s)
    }

    builder = if is_url?(source)
      Anvil::Builder.new(source)
    else
      manifest = Anvil::Manifest.new(File.expand_path(source))
      upload_missing manifest
      manifest
    end

    slug_url = builder.build(build_options) do |chunk|
      print chunk
    end

    old_stdout.puts slug_url if options[:pipeline]

    slug_url
  end

  def self.version
    puts Anvil::VERSION
  end

  def self.is_url?(string)
    URI.parse(string).scheme rescue nil
  end

  def self.prepare_buildpack(buildpack)
    if buildpack == ""
      buildpack
    elsif is_url?(buildpack)
      buildpack
    elsif buildpack =~ /\A\w+\/\w+\Z/
      "http://buildkits-dev.s3.amazonaws.com/buildpacks/#{buildpack}.tgz"
    elsif File.exists?(buildpack) && File.directory?(buildpack)
      manifest = Anvil::Manifest.new(buildpack)
      upload_missing manifest, "buildpack"
      manifest.save
    else
      error "unrecognized buildpack specification: #{buildpack}"
    end
  end

  def self.upload_missing(manifest, title="app")
    print "Checking for files to sync for #{title}... "
    missing = manifest.missing
    puts "done, #{missing.length} files needed"

    return if missing.length.zero?

    queue = Queue.new
    total_size = missing.map { |hash, file| file["size"].to_i }.inject(&:+)

    display = Thread.new do
      Progress.start "Uploading", total_size
      while (msg = queue.pop).first != :done
        case msg.first
          when :step then Progress.step msg.last.to_i
        end
      end
      puts "Uploading... done                                    "
    end

    if missing.length > 0
      manifest.upload(missing.keys) do |file|
        queue << [:step, file["size"].to_i]
      end
      queue << [:done, nil]
    end

    display.join
  end

end
