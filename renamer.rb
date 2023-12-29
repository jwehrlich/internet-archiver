#!/usr/bin/env ruby

# frozen_string_literal: true

require 'fileutils'
require 'optparse'

class Renamer
  def self.process(options)
    interval = options[:interval]

    episode = 1
    Dir["#{options[:path]}/*"].sort.each do |file_path|
      if File.file?(file_path)
        file_extension = File.extname(file_path).strip.downcase[1..-1]
        new_path = "%s/%s%02d" % [options[:path], options[:prefix], episode]

        if interval > 1
          episode += interval - 1
          new_path += "-#{episode}"
        end

        new_path += ".#{file_extension}"
        puts "Renaming \"#{file_path}\" to \"#{new_path}\""
        File.rename(file_path, new_path) unless options[:dry_run]

        episode += 1
      end
    end
  end
end


def help_menu_and_exit(exit_code: 0)
  puts <<-"EOHELP"
Internet Archive - Archiver

Usage: #{__FILE__} --path /path/to/dir --prefix="Show Title - S<season_num>E"

OPTIONS
--path     : Content Key
--prefix   : Extension must match given value
--dry-run  : Print the name change only
--interval : The number of episodes per file (default 1)
--help     : help

  EOHELP
  exit(exit_code)
end

if File.expand_path($PROGRAM_NAME) == File.expand_path(__FILE__)
  options = {interval: 1, dry_run: false}
  parser = OptionParser.new do |opts|
    opts.on('-p', '--path path') do |path|
      options[:path] = path
    end

    opts.on('-P', '--prefix prefix') do |prefix|
      options[:prefix] = prefix
    end

    opts.on('-i', '--interval interval') do |interval|
      options[:interval] = interval.to_i
    end

    opts.on('-d', '--dry-run') do
      options[:dry_run] = true
    end

    opts.on('-h', '--help', 'help menu') do
      help_menu_and_exit
    end
  end

  begin
    parser.parse!
  rescue => ex
    puts ex
    help_menu_and_exit(exit_code: 1)
  end

  Renamer.process(options)
end
