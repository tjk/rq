require 'vendor/environment'
require 'code/rule_processor'
require 'code/queueclient'
require 'code/errors'

def check_usage(arg_list)
  if not arg_list.length > 0 or arg_list.include?('-h') or arg_list.include?('--help')
    puts "Valid commands are:"
    puts "  " + Commands.new.public_methods.grep(/^cmd_/).each{|c| c.to_s.gsub!(/^cmd_/, '') }.sort.join("\n  ")
    exit 1
  end
end

def process_args(arg_list)
  input = { }

  input[:cmd]  = arg_list.shift
  input[:xtra] = []

  # TODO: do this in a functional manner to cleanse
  i = 0
  while i < arg_list.length
    if arg_list[i].index('--')
      # Ok, we have a param

      # ... does it have an '='
      if arg_list[i].index('=')
        parts = arg_list[i].split('=', 2)
        input[parts[0][2..-1]] = parts[1]
        i += 1
        next
      elsif (i+1 < arg_list.length) && (arg_list[i+1].index('--') == nil)
        input[arg_list[i][2..-1]] = arg_list[i+1]
        i += 2
        next
      end

      input[arg_list[i][2..-1]] = true
      i += 1
    else
      input[:xtra] << arg_list[i]
      i += 1
    end
  end

  input
end

class Commands
  def get_queue_client(q_name)
    RQ::QueueClient.new(q_name)
  end

  # Create a message
  #   - 'dest' queue
  #   - 'src' id
  #   - param[1234]
  def cmd_sendmesg(args)
    q_name = args['dest']
    raise RQ::RqMissingArgument if not q_name

    if q_name.start_with?('http:')
      raise RQ::RqCannotRelay if !args.has_key?('relay-ok') # throw :halt, [404, 'Sorry - cannot relay message']
      q_name = 'relay'
    end

    qc = get_queue_client(q_name)

    # Construct message
    mesg = {}
    keys = %w(dest src count max_count param1 param2 param3 param4 due force_remote)
    keys.each do |key|
      next unless args.has_key?(key)
      mesg[key] = args[key]
    end
    result = qc.create_message(mesg)
    print "#{result[0]} #{result[1]}\n"
    result[0] == "ok" ? 0 : 1
  end

  def cmd_prepmesg(args)
    q_name = args['dest']
    raise RQ::RqMissingArgument if not q_name

    if q_name.start_with?('http:')
      raise RQ::RqCannotRelay if !args.has_key?('relay-ok') # throw :halt, [404, 'Sorry - cannot relay message']
      q_name = 'relay'
    end

    qc = get_queue_client(q_name)

    # Construct message
    mesg = {}
    keys = %w(dest src count max_count param1 param2 param3 param4 due force_remote)
    keys.each do |key|
      next unless args.has_key?(key)
      mesg[key] = args[key]
    end
    result = qc.prep_message(mesg)
    print "#{result[0]} #{result[1]}\n"
    result[0] == "ok" ? 0 : 1
  end

  def check_attachment(msg)
    # simple early check, ok, now check for pathname
    return [false, "No such file #{msg['pathname']} to attach to message"] unless File.exists?(msg['pathname'])
    return [false, "Attachment currently cannot be a directory #{msg['pathname']}"] if File.directory?(msg['pathname'])
    return [false, "Attachment currently cannot be read: #{msg['pathname']}"] unless File.readable?(msg['pathname'])
    return [false, "Attachment currently not of supported type: #{msg['pathname']}"] unless File.file?(msg['pathname'])
    return [true, '']
  end

  def cmd_attachmesg(args)
    full_mesg_id = args['msg_id']
    raise RQ::RqMissingArgument if not full_mesg_id

    q_name = full_mesg_id[/\/q\/([^\/]+)/, 1]
    msg_id = full_mesg_id[/\/q\/[^\/]+\/([^\/]+)/, 1]

    qc = get_queue_client(q_name)

    # Construct message for queue mgr
    msg = {'msg_id' => msg_id}
    keys = %w(pathname name local_fs_only)
    keys.each do |key|
      next unless args.has_key?(key)
      msg[key] = args[key]
    end

    msg['pathname'] = File.expand_path(msg['pathname'])
    results = check_attachment(msg)
    raise RQ::RqError(results[0]) if not results[0] # throw :halt, [404, "404 - #{results[0]}"]
    result = qc.attach_message(msg)
    print "#{result[0]} #{result[1]} for Message: #{full_mesg_id} attachment\n"
    result[0] == "ok" ? 0 : 1
  end

  def cmd_commitmesg(args)
    full_mesg_id = args['msg_id']
    raise RQ::RqMissingArgument if not full_mesg_id

    q_name = full_mesg_id[/\/q\/([^\/]+)/, 1]
    msg_id = full_mesg_id[/\/q\/[^\/]+\/([^\/]+)/, 1]

    qc = get_queue_client(q_name)

    # Construct message for queue mgr
    mesg = {'msg_id' => msg_id }
    result = qc.commit_message(mesg)
    print "#{result[0]} #{result[1]}\n"
    result[0] == "ok" ? 0 : 1
    #p "#{result} for Message: #{mesg['msg-id']} committed"
  end

  def cmd_statusmesg(args)
    full_mesg_id = args['msg_id']
    raise RQ::RqMissingArgument if not full_mesg_id

    q_name = full_mesg_id[/\/q\/([^\/]+)/, 1]
    msg_id = full_mesg_id[/\/q\/[^\/]+\/([^\/]+)/, 1]

    qc = get_queue_client(q_name)

    # Construct message for queue mgr
    mesg = {'msg_id' => msg_id }
    result = qc.get_message_status(mesg)
    if result[0] == 'ok'
      print "#{result[0]} #{result[1]['status']}\n"
    else
      print "#{result[0]} #{result[1]}\n"
    end
    result[0] == "ok" ? 0 : 1
  end

  def cmd_state(args)
    full_mesg_id = args['msg_id']
    raise RQ::RqMissingArgument if not full_mesg_id

    q_name = full_mesg_id[/\/q\/([^\/]+)/, 1]
    msg_id = full_mesg_id[/\/q\/[^\/]+\/([^\/]+)/, 1]

    qc = get_queue_client(q_name)

    # Construct message for queue mgr
    mesg = {'msg_id' => msg_id }
    result = qc.get_message_state(mesg)
    if result[0] == 'ok'
      print "#{result[0]} #{result[1]}\n"
    else
      print "#{result[0]} #{result[1]}\n"
    end
    result[0] == "ok" ? 0 : 1
  end

  def cmd_statuscountmesg(args)
    full_mesg_id = args['msg_id']
    raise RQ::RqMissingArgument if not full_mesg_id

    q_name = full_mesg_id[/\/q\/([^\/]+)/, 1]
    msg_id = full_mesg_id[/\/q\/[^\/]+\/([^\/]+)/, 1]

    qc = get_queue_client(q_name)

    # Construct message for queue mgr
    mesg = {'msg_id' => msg_id }
    result = qc.get_message(mesg)
    if result[0] == 'ok'
      print "#{result[0]} #{result[1].fetch('count', '0')}\n"
    else
      print "#{result[0]} #{result[1]}\n"
    end
    result[0] == "ok" ? 0 : 1
  end

  def cmd_single_que(args)
    q_name = args['dest']
    raise RQ::RqMissingArgument if not q_name

    qc = get_queue_client(q_name)

    # Construct message
    mesg = {}
    keys = %w(dest src count max_count param1 param2 param3 param4 due force_remote)
    keys.each do |key|
      next unless args.has_key?(key)
      mesg[key] = args[key]
    end
    result = qc.single_que(mesg)
    print "#{result[0]} #{result[1]}\n"
    result[0] == "ok" ? 0 : 1
  end

  def cmd_attachstatusmesg(args)
    full_mesg_id = args['msg_id']
    raise RQ::RqMissingArgument if not full_mesg_id

    q_name = full_mesg_id[/\/q\/([^\/]+)/, 1]
    msg_id = full_mesg_id[/\/q\/[^\/]+\/([^\/]+)/, 1]

    qc = get_queue_client(q_name)

    # Construct message for queue mgr
    mesg = {'msg_id' => msg_id }
    result = qc.get_message(mesg)
    if result[0] == 'ok'
      ents = []
      if result[1].has_key?('_attachments')
        result[1]['_attachments'].each do |k,v|
          ents << [k, v['md5'], v['size'], v['path']]
        end
      end
      print "#{result[0]} #{ents.length}\n"
      ents.each do |ent|
        print "#{ent[0]} #{ent[1]} #{ent[2]} #{ent[3]}\n"
      end
    else
      print "#{result[0]} #{result[1]}\n"
    end
    result[0] == "ok" ? 0 : 1
  end

  def cmd_clone(args)
    full_mesg_id = args['msg_id']
    raise RQ::RqMissingArgument if not full_mesg_id

    q_name = full_mesg_id[/\/q\/([^\/]+)/, 1]
    msg_id = full_mesg_id[/\/q\/[^\/]+\/([^\/]+)/, 1]

    qc = get_queue_client(q_name)

    mesg = {'msg_id' => msg_id }
    result = qc.clone_message(mesg)
    print "#{result[0]} #{result[1]}\n"
    result[0] == "ok" ? 0 : 1
  end

  def cmd_verify_rules(args)
    raise RQ::RqMissingArgument if not args['path']

    rp = RQ::RuleProcessor.process_pathname(args['path'], args['verbose'])

    if rp == nil
      puts "fail bad router rules file"
      return 1
    else
      if args['verbose']
        rp.rules.each {|o| p o}
      end
      puts "ok"
      return 0
    end
  end
end

# BEGIN THINGS THAT RUN

args = check_usage(ARGV) || process_args(ARGV)

retval = 0
cmd = "cmd_#{args[:cmd]}"
cmds = Commands.new

if cmds.respond_to? cmd
  retval = cmds.send cmd, args
else
  warn "Command not found: #{args[:cmd]} (#{cmd})"
  retval = 1
end

exit retval
