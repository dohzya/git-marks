#!/usr/bin/env ruby

begin
  require 'yaml'
  require 'term/ansicolor'
  class String
    include Term::ANSIColor
    #  be careful with that
    def method_missing(meth,*args)
      self
    end
  end
rescue
end

# todo:
# - options:
#   - do not re-write file
# - better cli:
#   - 'git mark (add)? rebasing to features/users/132'
#   - 'git mark del rebasing to features/users/132'
#   - 'git mark del rebasing' => 'to *'
#   - 'git mark (show)? master'
#   - 'git mark list rebasing'
# - base of known marks:
#   - coloration
#   - priority:
#     - 'git mark list > merging'
#     - sort by priority

def next_arg(arg, args)
  arg =~ /=/ ? arg.sub(/.*=\s*/,'') : args.shift
end

def glob_to_reg(glob)
  reg = glob.dup
  reg.gsub!(/[*]/, '.*')
  reg.gsub!(/[?]/, '.')
  Regexp.new(reg)
end

opts = {
  :patterns => [],
  :selects => [],
  :excludes => [],
  :only => [],
  :add => [],
  :delete => [],
  :list => [],
}
args = ARGV.dup
while arg = args.shift
  case arg
  when /^--marks-file/
    opts[:marks_file] = next_arg(arg, args)
  when /^--config-file$/
    opts[:config_file] = next_arg(arg, args)

  when /^-h|--heads$/
    opts[:selects] << 'refs/heads/'
  when /^-r|--remote$/
    opts[:selects] << 'refs/remotes/'
  when /^-A|--All$/
    opts[:selects] << 'refs/(heads|remotes)/'
  when /^-a|--all$/
    opts[:selects] << '*'
  when /^-e|--exclude/
    opts[:excludes] << next_arg(arg, args)
  when /^-o|--only/
    opts[:only] << next_arg(arg, args)

  when /^-l|--list/,'list'
    opts[:list] << next_arg(arg, args)

  when 'add'
    opts[:add] << next_arg(arg, args)
  when 'delete','del','rm'
    opts[:delete] << next_arg(arg, args)

  when '--'
    opts[:patterns].concat(args)
    args.clear
  else
    opts[:patterns] << arg
  end
end

opts[:marks_file] ||= ENV['GIT_MARKS_FILE'] || %x(git config --get marks.file || echo $(git rev-parse --git-dir)/marks)
opts[:marks_file].sub!(/\r?\n?$/,'')

opts[:config_file] ||= ENV['GIT_MARKS_CONFIG_FILE'] || %x(git config --get marks.configfile || echo $(git rev-parse --git-dir)/info/marks)
opts[:config_file].sub!(/\r?\n?$/,'')

opts[:selects] << 'refs/heads/' if opts[:selects].empty?
opts[:selects].map!{|ptn| glob_to_reg(ptn) }
refs = {}
show = []
%x(git show-ref --abbrev).each_line do |line|
  hash, ref = line.split(' ')
  refs[ref] = [hash, []]
  show << ref if opts[:selects].any?{|ptn| ref =~ ptn }
end

if File.exists? opts[:marks_file]
  File.open(opts[:marks_file]) do |file|
    file.each_line do |line|
      line.sub!(/\n?\r?$/,'')
      ref, marks = line.match(/([^ ]+) (.*)/).captures
      marks = marks.split(/\s*,\s*/).sort
      if refs.include? ref
        refs[ref][1] = [*marks]
      end
    end
  end
end

if File.exists? opts[:config_file]
  config = YAML.load_file(opts[:config_file])
else
  config = {}
end
%w(types marks colors).each{|n| config[n] ||= {} }
%w(priority).each{|n| config[n] ||= [] }
config['types'].each do |types|
  types.each do |type, marks|
    marks.each do |mark|
      mark.each do |name, color|
        config['marks'][name] = type
        config['colors'][name] = color
        config['priority'] << name unless config['priority'].include?(name)
      end
    end
  end
end

if opts[:list].empty?
  opts[:patterns] << '*' if opts[:patterns].empty?
  opts[:patterns].map!{|ptn| glob_to_reg(ptn) }
  opts[:excludes].map!{|ptn| glob_to_reg(ptn) }
  show.map! do |ref|
    case
    when opts[:excludes].any?{|ptn| ref =~ ptn }
    when !opts[:only].all?{|ptn| ref =~ ptn }
    when opts[:patterns].any?{|ptn| ref =~ ptn }
      ref
    end
  end
else
  opts[:list].map!{|ptn| glob_to_reg(ptn) }
  opts[:excludes].map!{|ptn| glob_to_reg(ptn) }
  show.map! do |ref|
    head, marks = refs[ref]
    case
    when opts[:excludes].any?{|ptn| marks.any?{|m| m =~ ptn } }
    when opts[:list].any?{|ptn| marks.any?{|m| m =~ ptn } }
      ref
    else
    end
  end
end
show.compact!

opts[:add].each do |add|
  add = add.split(/\s*,\s*/)
  show.each do |ref|
    refs[ref][1] = (refs[ref][1] + add).uniq
  end
end

opts[:delete].each do |delete|
  delete = delete.split(/\s*,\s*/)
  show.each do |ref|
    delete.each{|d| refs[ref][1].delete(d) }
  end
end

show.map! do |ref|
  [ref, ref.sub(%r[^refs/(heads/|remotes/)?],'')]
end

max = show.map{|r,s| s.length}.max || 0
max = 50 if max > 50
show.each do |ref, short_ref|
  hash, marks = refs[ref]
  marks = [*marks].map do |mark|
    color = config['colors'][mark]
    if color
      if config['marks'][mark] == config['color-ref']
        short_ref = short_ref.send(color)
      end
      mark.send(color)
    else
      mark
    end
  end
  _max = short_ref =~ /(?:(\e\[\d*m).*)+/ ? max+9 : max # TODO should count the *real* number of non-shown chars
  to_puts = "%-#{_max}s %s %s" % [short_ref, hash, marks.join(', ')]
  puts to_puts
end

File.open(opts[:marks_file], 'w') do |file|
  file.puts refs.map{|r,(h,m)| "#{r} #{[*m].join(",")}" }.join("\n")
end

