# encoding: UTF-8
#
# Yüzey Oluştur (Make Faces) - SketchUp eklentisi
# Seçili kenarlardan kapalı, düzlemsel döngüler için yüzey (face) oluşturur.
#
# Uyumluluk: SketchUp 2017 - 2021+ (Ruby 2.x)

require 'sketchup.rb'
require 'extensions.rb'

module MFMakeFaces

  PLUGIN_NAME    = 'Yüzey Oluştur (Make Faces)'.freeze
  PLUGIN_VERSION = '1.5.0'.freeze
  PLUGIN_DIR     = File.join(File.dirname(__FILE__), 'mf_make_faces').freeze

  unless file_loaded?(__FILE__)
    ext = SketchupExtension.new(PLUGIN_NAME, File.join(PLUGIN_DIR, 'main'))
    ext.version     = PLUGIN_VERSION
    ext.creator     = 'Fatih'
    ext.copyright   = "2026"
    ext.description = 'Seçili kenarlardan yüzey oluşturur, aynı düzlemdeki ' \
                      'yüzeyleri bölen gereksiz çizgileri temizler ve ayrı ' \
                      'push/pull yapılmış bitişik hacimlerin arasındaki iç ' \
                      'bölücü yüzeyleri silerek onları birleştirir.'
    Sketchup.register_extension(ext, true)
    file_loaded(__FILE__)
  end

end
