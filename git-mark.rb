#!/usr/bin/env ruby

# todo:
# - options:
#   - do not re-write file
# - coloration
# - better cli:
#   - 'git mark (add)? rebasing to features/users/132'
#   - 'git mark del rebasing to features/users/132'
#   - 'git mark del rebasing' => 'to *'
#   - 'git mark (show)? master'
#   - 'git mark list rebasing'
# - structure:
#   - 'git mark list < rebasing' (assuming 'rebasing' is a know and comparable state)

opts = {
  :patterns => [],
  :excludes => ['refs/remotes/'],
  :add => [],
  :delete => [],
  :list => [],
  :exclude_list => [],
}
args = ARGV.dup
while arg = args.shift
  case arg
  when /^--marks-file/
    opts[:file] = arg =~ /=/ ? arg.sub(/.*=\s*/,'') : args.shift

  when /^-r|--remote$/
    opts[:excludes].delete('refs/remotes/')
    opts[:excludes] << 'refs/heads/'
  when /^-A|--All$/
    opts[:excludes].delete('refs/heads/')
    opts[:excludes].delete('refs/remotes/')
  when /^-a|--all$/
    opts[:excludes].delete('refs/heads/')
    opts[:excludes].delete('refs/remotes/')
  when /^-e|--exclude/
    opts[:excludes] = arg =~ /=/ ? arg.sub(/.*=\s*/,'') : args.shift

  when /^-l|--list/
    opts[:list] << (arg =~ /=/ ? arg.sub(/.*=\s*/,'') : args.shift)
  when /^-el|--exclude-list/
    opts[:exclude_list] << (arg =~ /=/ ? arg.sub(/.*=\s*/,'') : args.shift)

  when /^-m|--message/
    opts[:add] << (arg =~ /=/ ? arg.sub(/.*=\s*/,'') : args.shift)
  when /^-d|--delete/
    opts[:delete] << (arg =~ /=/ ? arg.sub(/.*=\s*/,'') : args.shift)

  when '--'
    opts[:patterns].concat(args)
    args.clear
  else
    opts[:patterns] << arg
  end
end

opts[:file] ||= ENV['GIT_MARKS_FILE'] || %x(git config --get marks.file || echo $(git rev-parse --git-dir)/marks)
opts[:file].sub!(/\r?\n?$/,'')

refs = {}
%x(git show-ref --abbrev).each_line do |line|
  hash, ref = line.split(' ')
  refs[ref] = [hash, []]
end

if File.exists? opts[:file]
  File.open(opts[:file]) do |file|
    file.each_line do |line|
      line.sub!(/\n?\r?$/,'')
      ref, marks = line.match(/([^ ]+) (.*)/).captures
      marks = marks.split(/\s*,\s*/)
      if refs.include? ref
        refs[ref][1] = [*marks]
      end
    end
  end
end

show = []
if opts[:list].empty?
  opts[:patterns].map!{|p| /^#{p.sub(/[*]/,'.*').sub(/[?]/,'.')}$/ }
  opts[:excludes].map!{|p| /^#{p.sub(/[*]/,'.*').sub(/[?]/,'.')}$/ }
  refs.each do |ref, (hash,marks)|
    case
    when opts[:excludes].any?{|p| ref =~ p }
      add = false
    when opts[:patterns].any?{|p| ref =~ p }
      add = true
    else
      add = false
    end
    show << ref if add
  end

  opts[:add].each do |add|
    add = add.split(/\s*,\s*/)
    show.each do |ref, short_ref|
      refs[ref][1].concat(add)
    end
  end

  opts[:delete].each do |delete|
    delete = delete.split(/\s*,\s*/)
    show.each do |ref, short_ref|
      delete.each{|d| refs[ref][1].delete(d) }
    end
  end
else
  opts[:list] = opts[:list].map{|l| /^#{l.sub(/[*]/,'.*').sub(/[?]/,'.').sub(/,/,'|')}$/ }
  opts[:exclude_list] = opts[:exclude_list].map{|l| /#{l.sub(/[*]/,'.*').sub(/[?]/,'.').sub(/,/,'|')}$/ }
  refs.each do |ref, (hash,marks)|
    case
    when opts[:exclude_list].any?{|p| marks.any?{|m| m =~ p } }
      add = false
    when opts[:list].any?{|p| marks.any?{|m| m =~ p } }
      add = true
    else
      add = false
    end
    show << ref if add
  end
end
show = show.inject({}) do |res, ref|
  res[ref] = ref.sub(%r[^refs/(heads/|remotes/)?],'')
  res
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
