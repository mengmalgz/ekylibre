module PdfPrinter
  extend ActiveSupport::Concern

  # return data
  def generate_report(template_name_or_path, options = {}, &block)
    template_path = to_template_path(template_name_or_path)
    report = ODFReport::Report.new(template_path, &block)
    to_pdf_data report, options
  end

  # return file
  def generate_report_file(template_name_or_path, &block)
    template_path = to_template_path(template_name_or_path)
    data = generate_report template_path, &block
    file = Tempfile.new(['source', '.pdf'])
    begin
      file.write data
      file.path
    ensure
      file.close
    end
  end

  # return file and store file in documents
  def generate_document(nature, key, template_name_or_path, mandatory = false, closer = nil, options = { archiving: :last }, &block)
    data = generate_report(template_name_or_path, options, &block)
    archive_report nature, key, data, mandatory, closer, options
  end

  # store file in document
  # nature must a Nomen::DocumentNature object
  def archive_report(nature, key, data_or_path, mandatory = false, closer = nil, options = { archiving: :last })
    data = data_or_path.is_a?(File) ? data_or_path : StringIO.new(data_or_path)
    name = options[:name] || [nature.human_name, key].join(' ')
    document = Document.create!(
                 nature: nature,
                 key: key,
                 name: name,
                 file: data,
                 file_file_name: "#{key}.pdf"
               )

    if mandatory
      sha256 = Digest::SHA256.file document.file.path
      crypto = GPGME::Crypto.new
      signature = crypto.clearsign(sha256.to_s, signer: ENV['GPG_EMAIL'])
      signature_path = document.file.path.gsub(/\.pdf/, '.asc')
      File.write(signature_path, signature)
      document.update!(sha256_fingerprint: sha256.to_s, signature: signature.to_s, mandatory: true, creator: closer, updater: closer)
    end
    document
  end

  def find_open_document_template(name)
    dir = Rails.root.join('config', 'locales')
    paths = [dir.join(I18n.locale.to_s, 'reporting', "#{name}.odt"),
             dir.join('eng', 'reporting', "#{name}.odt"),
             dir.join('fra', 'reporting', "#{name}.odt")]
    paths.detect(&:exist?)
  end

  private

  def to_template_path(name_or_path)
    return name_or_path unless name_or_path.is_a?(String)
    directory = self.class.name.gsub(/Printer$/, '').underscore
    file_name = "#{name_or_path}.odt"
    Rails.root.join('config', 'locales', I18n.locale.to_s, 'reporting', directory, file_name)
  end

  def to_pdf_data(report, options = {})
    Dir.mktmpdir do |directory|
      directory_path = Pathname.new(directory)
      odf_path = directory_path.join('source.odf').to_s
      report.generate odf_path
      convert_to_pdf directory, odf_path
      pdf_path = directory_path.join('source.pdf').to_s
      remove_empty_tailing_page(pdf_path) if options[:multipage]
      fill_checks(pdf_path, options[:checks]) if options[:checks]
      File.read pdf_path
    end
  end

  def convert_to_pdf(directory, odf_path)
    system "soffice --headless --convert-to pdf --outdir #{directory} #{odf_path}"
  end

  def remove_empty_tailing_page(pdf_path)
    pdf = CombinePDF.load(pdf_path)
    pdf.remove(pdf.pages.count - 1)
    pdf.save pdf_path
  end

  def fill_checks(pdf_path, checks)
    pdf = CombinePDF.load(pdf_path)
    properties = { font_size: 11, height: 12, width: 250, text_align: :left }
    checks.each_with_index do |check, index|
      pdf.pages[index].textbox check[:amount], properties.merge({ x: 460, y: 142 })
      pdf.pages[index].textbox check[:amount_to_letter], properties.merge({ x: 70, y: 155 })
      pdf.pages[index].textbox check[:payee], properties.merge({ x: 78, y: 132 })
      pdf.pages[index].textbox check[:company_town], properties.merge({ x: 450, y: 116 })
      pdf.pages[index].textbox check[:paid_at], properties.merge({ x: 450, y: 101 })
    end
    pdf.save pdf_path
  end
end
