#!/usr/bin/env ruby

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
    opts[:file] = next_arg(arg, args)

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

opts[:file] ||= ENV['GIT_MARKS_FILE'] || %x(git config --get marks.file || echo $(git rev-parse --git-dir)/marks)
opts[:file].sub!(/\r?\n?$/,'')

opts[:selects] << 'refs/heads/' if opts[:selects].empty?
opts[:selects].map!{|p| glob_to_reg(p) }
refs = {}
show = []
%x(git show-ref --abbrev).each_line do |line|
  hash, ref = line.split(' ')
  refs[ref] = [hash, []]
  show << ref if opts[:selects].any?{|p| ref =~ p }
end

if File.exists? opts[:file]
  File.open(opts[:file]) do |file|
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

if opts[:list].empty?
  opts[:patterns] << '*' if opts[:patterns].empty?
  opts[:patterns].map!{|p| glob_to_reg(p) }
  opts[:excludes].map!{|p| glob_to_reg(p) }
  show.map! do |ref|
    case
    when opts[:excludes].any?{|p| ref =~ p }
    when !opts[:only].all?{|p| ref =~ p }
    when opts[:patterns].any?{|p| ref =~ p }
      ref
    end
  end
else
  opts[:list].map!{|p| glob_to_reg(p) }
  opts[:excludes].map!{|p| glob_to_reg(p) }
  show.map! do |ref|
    head, marks = refs[ref]
    case
    when opts[:excludes].any?{|p| marks.any?{|m| m =~ p } }
    when opts[:list].any?{|p| marks.any?{|m| m =~ p } }
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
  hash, *marks = refs[ref]
  puts("%-#{max}s %s %s" % [short_ref, hash, marks.join(', ')])
end

File.open(opts[:file], 'w') do |file|
  file.puts refs.map{|r,(h,m)| "#{r} #{[*m].join(",")}" }.join("\n")
end

