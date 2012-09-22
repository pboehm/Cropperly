# encoding: UTF-8

require 'sinatra'
require 'digest/sha1'
require 'fileutils'
require 'json'
require 'prawn'

configure { set :server, :puma }

get '/' do
  erb :index
end

post '/new' do
  if params['file']
    @pdf = Pdf.new({
            :tempfile => params['file'][:tempfile],
            :filename => params['file'][:filename]
            })
    return redirect("/crop/#{@pdf.sha1}/")
  end
end

get '/crop/:sha1/' do
  @pdf = Pdf.new({ :sha1 => params[:sha1]})
  erb :crop
end

post '/preview/:sha1/' do
  content_type :json

  if params[:top] && params[:right] && params[:bottom] && params[:left]
    @pdf = Pdf.new({ :sha1 => params[:sha1]})
    url = @pdf.generate_preview(params[:top].to_i, params[:right].to_i,
                                params[:bottom].to_i, params[:left].to_i)
    return { url: url + "?#{Time.now.to_i.to_s}" }.to_json
  end
  "MISSING_FIELDS".to_json
end


class Pdf
  attr_reader :sha1, :filename

  STORAGE_DIR = 'public/uploads/'
  DEFAULT_FILENAME = "original.pdf"
  PREVIEW_FILENAME = "preview.pdf"
  FILENAME_STORAGE = "__filename.txt"

  def initialize(args)
    if args[:tempfile] && args[:filename]

      @sha1 = sha1sum(args[:tempfile])
      @tempfile = args[:tempfile]
      @filename = args[:filename]

      unless File.directory?(project_dir)
        FileUtils.mkdir(project_dir)
        move_tempfile
        filename(args[:filename])
      end

    elsif args[:sha1]
      @sha1 = args[:sha1]
      @filename = filename
    end
  end

  def generate_preview(top=5, right=5, bottom=5, left=5)
    crop_pdf(File.join(project_dir, DEFAULT_FILENAME),
             File.join(project_dir, PREVIEW_FILENAME),
             { top: top, right: right, bottom: bottom, left: left }
            )

    File.join('/', "uploads", @sha1, PREVIEW_FILENAME)
  end

  def project_dir
    File.join(STORAGE_DIR, @sha1)
  end

  def sha1sum(tempfile)
    file = File.open(tempfile, "rb")
    Digest::SHA1.hexdigest(file.read)
  end

  def filename(name=nil)
    storage = File.join(project_dir, FILENAME_STORAGE)

    if name
      # write filename if it is supplied
      File.open(storage, 'w') { |f| f.write(name) }
    end

    File.open(storage, 'r') { |f| f.read }
  end

  def move_tempfile
    FileUtils.mv @tempfile, File.join(project_dir, DEFAULT_FILENAME)
  end

  def crop_pdf(src_file, dest_file, options={})
    Prawn::Document.generate(dest_file, template: src_file) do
      (1..page_count).each do |n|
        go_to_page(n)
        x1, y1, x2, y2 = page.dictionary.data[:MediaBox]
        x1_new = (x1 + (x2 - x1) * (options[:left]   / 100.0)).to_i
        x2_new = (x2 - (x2 - x1) * (options[:right]  / 100.0)).to_i
        y1_new = (y1 + (y2 - y1) * (options[:bottom] / 100.0)).to_i
        y2_new = (y2 - (y2 - y1) * (options[:top]    / 100.0)).to_i
        page.dictionary.data[:MediaBox] = [x1_new, y1_new, x2_new, y2_new]
      end
    end
  end
end
