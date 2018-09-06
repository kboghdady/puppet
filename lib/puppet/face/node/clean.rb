Puppet::Face.define(:node, '0.0.1') do
  action(:clean) do

    summary _("Clean up signed certs, cached facts, node objects, and reports for a node stored by the puppetmaster")
    arguments _("<host1> [<host2> ...]")
    description <<-'EOT'
      Cleans up the following information a puppet master knows about a node:

      <Signed certificates> - ($vardir/ssl/ca/signed/node.domain.pem)

      <Cached facts> - ($vardir/yaml/facts/node.domain.yaml)

      <Cached node objects> - ($vardir/yaml/node/node.domain.yaml)

      <Reports> - ($vardir/reports/node.domain)

    EOT

    when_invoked do |*args|
      nodes = args[0..-2]
      options = args.last
      raise _("At least one node should be passed") if nodes.empty? || nodes == options

      # This seems really bad; run_mode should be set as part of a class
      # definition, and should not be modifiable beyond that.  This is one of
      # the only places left in the code that tries to manipulate it. Other
      # parts of code that handle certificates behave differently if the
      # run_mode is master. Those other behaviors are needed for cleaning the
      # certificates correctly.
      Puppet.settings.preferred_run_mode = "master"

      Puppet::Node::Facts.indirection.terminus_class = :yaml
      Puppet::Node::Facts.indirection.cache_class = :yaml
      Puppet::Node.indirection.terminus_class = :yaml
      Puppet::Node.indirection.cache_class = :yaml

      nodes.each { |node| cleanup(node.downcase) }
    end
  end

  def cleanup(node)
    clean_cert(node)
    clean_cached_facts(node)
    clean_cached_node(node)
    clean_reports(node)
  end

  class LoggerIO
    def err(message)
      Puppet.err(message) unless message =~ /^\s*Error:\s*/
    end

    def inform(message)
      Puppet.notice(message)
    end
  end

  # clean signed cert for +host+
  def clean_cert(node)
    begin
      require 'puppetserver/ca/cli'
      Puppetserver::Ca::Action::Clean.new(LoggerIO.new).run({ 'certnames' => [node] })
    rescue LoadError => e
      Puppet.warning _("Unable to clean up certs for %{node}: %{error}") % { node: node, error: e }
    end
  end

  # clean facts for +host+
  def clean_cached_facts(node)
    Puppet::Node::Facts.indirection.destroy(node)
    Puppet.info _("%{node}'s facts removed") % { node: node }
  end

  # clean cached node +host+
  def clean_cached_node(node)
    Puppet::Node.indirection.destroy(node)
    Puppet.info _("%{node}'s cached node removed") % { node: node }
  end

  # clean node reports for +host+
  def clean_reports(node)
    Puppet::Transaction::Report.indirection.destroy(node)
    Puppet.info _("%{node}'s reports removed") % { node: node }
  end

  def environment
    @environment ||= Puppet.lookup(:current_environment)
  end

  def type_is_ensurable(resource)
    if (type = Puppet::Type.type(resource.restype)) && type.validattr?(:ensure)
      return true
    else
      type = environment.known_resource_types.find_definition(resource.restype)
      return true if type && type.arguments.keys.include?('ensure')
    end
    return false
  end
end
