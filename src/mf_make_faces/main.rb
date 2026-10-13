# encoding: UTF-8
#
# Yüzey Oluştur (Make Faces) - ana kod
#
# Üç iş yapar:
#   1) Yüzey oluşturma: her kenar için Sketchup::Edge#find_faces çağrılır;
#      SketchUp kapalı ve düzlemsel döngüleri bulup eksik yüzeyleri oluşturur.
#   2) Kenar temizliği: iki tarafındaki yüzeyler aynı düzlemde olan, yani
#      yüzeyi gereksiz yere bölen ayırıcı çizgiler silinir.
#   3) Hacim birleştirme: ayrı ayrı push/pull yapılmış bitişik parçaların
#      arasında kalan "iç bölücü" yüzeyler silinir; ardından ortaya çıkan
#      gereksiz çizgiler de (2) ile temizlenir.
#
# (3) neden gerekli: iki parça yan yana push/pull edilince aralarında bir
# bölücü yüzey kalır. Dıştan görünen ayırıcı çizginin 2 değil 3 yüzeyi olur,
# bu yüzden salt kenar temizliği o çizgiye dokunamaz. Önce bölücü yüzey
# gitmeli, sonra çizgi 2 eş düzlemli yüzeye düşüp silinebilir hale gelir.

require 'sketchup.rb'

module MFMakeFaces

  PREF_KEY   = 'MFMakeFaces'.freeze
  ICONS_DIR  = File.join(File.dirname(__FILE__), 'icons').freeze

  # main.rb tek başına yüklenirse diye güvenlik ağı.
  PLUGIN_NAME = 'Yüzey Oluştur (Make Faces)'.freeze unless defined?(PLUGIN_NAME)

  class << self

    # --- Ayarlar ------------------------------------------------------------

    def read_pref(key, fallback)
      value = Sketchup.read_default(PREF_KEY, key, fallback)
      value.nil? ? fallback : value
    end

    def write_pref(key, value)
      Sketchup.write_default(PREF_KEY, key, value ? true : false)
    end

    # Grup / bileşen içlerine girilsin mi?
    def deep?
      read_pref('deep', true)
    end

    def deep=(value)
      write_pref('deep', value)
    end

    # Malzeme / tag farkı olan yüzeyler birleştirilmesin mi?
    def strict?
      read_pref('strict', true)
    end

    def strict=(value)
      write_pref('strict', value)
    end

    # Hiçbir yüzeye ait olmayan (boştaki) çizgiler de silinsin mi?
    def strays?
      read_pref('strays', false)
    end

    def strays=(value)
      write_pref('strays', value)
    end

    # İşlem sonunda yeni yüzeyler seçili kalsın mı?
    def select_new?
      read_pref('select_new', false)
    end

    def select_new=(value)
      write_pref('select_new', value)
    end

    # --- Toplama ------------------------------------------------------------

    # Verilen varlık listesinden kenarları toplar.
    # Yüz seçiliyse o yüzün kenarları da eklenir.
    # deep = true ise grup / bileşen tanımlarının içine de girilir.
    def collect_edges(entities, deep, out = [], seen_defs = {})
      entities.each do |entity|
        next unless entity.valid?
        case entity
        when Sketchup::Edge
          out << entity
        when Sketchup::Face
          out.concat(entity.edges)
        when Sketchup::Group, Sketchup::ComponentInstance
          next unless deep
          definition = entity.definition
          next if definition.nil?
          next if seen_defs.key?(definition.entityID)
          seen_defs[definition.entityID] = true
          collect_edges(definition.entities, deep, out, seen_defs)
        end
      end
      out
    end

    def unique(entities)
      entities.uniq { |entity| entity.entityID }
    end

    # Kenarlara komşu tüm yüzeyler.
    def faces_of(edges)
      faces = []
      edges.each do |edge|
        next unless edge.valid?
        faces.concat(edge.faces)
      end
      unique(faces)
    end

    # Hangi varlıklar üzerinde çalışılacak?
    #   :selection -> yalnızca seçim
    #   :context   -> aktif çizim bağlamının tamamı
    #   :auto      -> seçim varsa seçim, yoksa aktif bağlam
    def resolve_source(model, scope)
      case scope
      when :selection
        model.selection
      when :context
        model.active_entities
      else
        model.selection.empty? ? model.active_entities : model.selection
      end
    end

    # --- Yüzey oluşturma ----------------------------------------------------

    # [oluşan yüzey sayısı, yeni yüzeyler] döner.
    def build_faces(edges)
      created   = 0
      new_faces = []
      total     = edges.size
      index     = 0

      edges.each do |edge|
        index += 1
        next unless edge.valid?

        before_ids = edge.faces.map { |face| face.entityID }
        count      = edge.find_faces.to_i

        if count > 0
          created += count
          if edge.valid?
            edge.faces.each do |face|
              new_faces << face unless before_ids.include?(face.entityID)
            end
          end
        end

        if (index % 200).zero?
          Sketchup.status_text = "Yüzey oluşturuluyor... #{index} / #{total}"
        end
      end

      [created, new_faces]
    end

    # --- Ortak testler ------------------------------------------------------

    # İki yüzey aynı düzlemde ve aynı yöne mi bakıyor?
    def coplanar?(face_a, face_b)
      return false unless face_a.normal.samedirection?(face_b.normal)
      same_plane?(face_a, face_b)
    end

    # Yön gözetmeksizin aynı düzlemde mi? (çakışık yüzeyleri yakalamak için)
    def same_plane?(face_a, face_b)
      plane = face_a.plane
      face_b.vertices.all? { |vertex| vertex.position.on_plane?(plane) }
    end

    # Listedeki yüzeyler arasında eş düzlemli ilk çifti döner, yoksa nil.
    def coplanar_pair(faces)
      faces.each_with_index do |face_a, i|
        ((i + 1)...faces.size).each do |j|
          return [face_a, faces[j]] if coplanar?(face_a, faces[j])
        end
      end
      nil
    end

    # Birleştirilmeleri bilgi kaybına yol açar mı?
    def mergeable?(face_a, face_b)
      return true unless strict?
      face_a.material == face_b.material &&
        face_a.back_material == face_b.back_material &&
        face_a.layer == face_b.layer
    end

    # --- Kenar temizliği ----------------------------------------------------

    # Gereksiz kenarlar: iki tarafı da aynı düzlemde olan ayırıcı çizgiler ve
    # (ayar açıksa) hiçbir yüzeye bağlı olmayan boştaki çizgiler.
    def find_redundant_edges(edges)
      victims = []
      total   = edges.size
      index   = 0

      edges.each do |edge|
        index += 1

        if (index % 500).zero?
          Sketchup.status_text = "Çizgiler taranıyor... #{index} / #{total}"
        end

        next unless edge.valid?

        faces = edge.faces

        if faces.empty?
          victims << edge if strays?
          next
        end

        next unless faces.size == 2

        face_a = faces[0]
        face_b = faces[1]
        next if face_a.entityID == face_b.entityID
        next unless coplanar?(face_a, face_b)
        next unless mergeable?(face_a, face_b)

        victims << edge
      end

      victims
    end

    # --- Hacim birleştirme (iç bölücü yüzeyler) -----------------------------

    # Bir yüzey, bitişik iki hacmin arasında kalmış "iç bölücü" mü?
    # Değilse nedenini anlatan bir metin, öyleyse nil döner.
    #
    # Şartlar (hepsi birden):
    #   * Yüzeyin HİÇBİR kenarı açık olmamalı: her kenarda en az 2 yüzey var.
    #     Yani yüzey her tarafından başka geometriye gömülü. Tek başına duran
    #     bir bölme duvarının serbest kenarları (1 yüzey) bunu geçemez.
    #   * En az bir kenarda, diğer yüzeyler arasında eş düzlemli ve aynı yöne
    #     bakan bir çift olmalı. Yani bu yüzey gerçekten sürekli bir yüzeyi
    #     bölüyor olmalı.
    #   * Yüzeyin kendisi o eş düzlemli çiftle AYNI düzlemde olmamalı; öyleyse
    #     bu bir çakışık (üst üste binmiş) yüzeydir, dokunulmaz.
    #   * "Malzeme / Tag Farkını Koru" açıkken eş düzlemli çiftler
    #     birleştirilebilir olmalı.
    def partition_reason(face)
      edges = face.edges
      return 'kenar sayısı 3ten az' if edges.size < 3

      seam = false

      edges.each_with_index do |edge, index|
        faces = edge.faces

        if faces.size < 2
          return "kenar #{index + 1}: yalnızca #{faces.size} yüzey var " \
                 '(açık/serbest kenar) - bu yüzey gömülü değil'
        end

        others = faces.reject { |other| other.entityID == face.entityID }
        pair = coplanar_pair(others)
        next if pair.nil?

        if same_plane?(pair[0], face)
          return "kenar #{index + 1}: yüzey, eş düzlemli komşularıyla aynı " \
                 'düzlemde (çakışık yüzey)'
        end

        unless mergeable?(pair[0], pair[1])
          return "kenar #{index + 1}: eş düzlemli yüzeylerin malzeme/tagi farklı"
        end

        seam = true
      end

      return 'hiçbir kenarında eş düzlemli yüzey çifti yok - bir yüzeyi bölmüyor' unless seam

      nil
    end

    def internal_partition?(face)
      partition_reason(face).nil?
    end

    def find_internal_partitions(faces)
      victims = []
      total   = faces.size
      index   = 0

      faces.each do |face|
        index += 1

        if (index % 500).zero?
          Sketchup.status_text = "İç yüzeyler taranıyor... #{index} / #{total}"
        end

        next unless face.valid?
        victims << face if internal_partition?(face)
      end

      victims
    end

    # --- Silme --------------------------------------------------------------

    # Varlıkları ait oldukları bağlama göre gruplayıp siler. Silinen sayıyı döner.
    def erase_grouped(entities_to_erase)
      buckets = {}

      entities_to_erase.each do |entity|
        next unless entity.valid?
        parent = entity.parent
        key = parent.is_a?(Sketchup::Model) ? :model : parent.entityID
        buckets[key] ||= [parent.entities, []]
        buckets[key][1] << entity
      end

      removed = 0
      buckets.each_value do |entities, list|
        list = list.select { |entity| entity.valid? }
        next if list.empty?
        entities.erase_entities(list)
        removed += list.size
      end
      removed
    end

    # --- Komut akışı --------------------------------------------------------

    # make  : yüzey oluştur
    # clean : gereksiz çizgileri temizle
    # merge : iç bölücü yüzeyleri sil (kenar temizliğini de zorunlu kılar)
    def perform(title, scope, make, clean, merge = false)
      model = Sketchup.active_model
      return if model.nil?

      clean = true if merge
      selection = model.selection

      if scope == :selection && selection.empty?
        UI.messagebox(
          "Önce kenar (ve/veya yüzey) seçin.\n\n" +
          "Tüm bağlamı işlemek için \"Aktif Bağlamın Tamamında\" komutunu kullanın."
        )
        return
      end

      edges = unique(collect_edges(resolve_source(model, scope), deep?))

      if edges.empty?
        UI.messagebox('İşlenecek geometri bulunamadı.')
        return
      end

      created   = 0
      merged    = 0
      removed   = 0
      new_faces = []

      model.start_operation(title, true)
      begin
        created, new_faces = build_faces(edges) if make

        if merge
          partitions = find_internal_partitions(faces_of(edges))
          # Bölücü yüzeyin kenarları, yüzey silindikten sonra temizlenebilir
          # hale gelir; tarama listesine ekleyelim.
          partitions.each { |face| edges.concat(face.edges) }
          edges  = unique(edges)
          merged = erase_grouped(partitions)
        end

        removed = erase_grouped(find_redundant_edges(edges)) if clean

        model.commit_operation
      rescue StandardError => error
        model.abort_operation
        Sketchup.status_text = ''
        UI.messagebox("İşlem sırasında hata oluştu:\n#{error.message}")
        return
      end

      if select_new? && !new_faces.empty?
        # Yalnızca aktif çizim bağlamındaki yüzeyler seçilebilir.
        active     = model.active_entities
        selectable = new_faces.select { |face| face.valid? && face.parent == active.parent }
        unless selectable.empty?
          selection.clear
          selection.add(selectable)
        end
      end

      Sketchup.status_text = report(make, clean, merge, created, removed, merged)
    end

    def report(make, clean, merge, created, removed, merged)
      parts = []
      if make
        parts << (created.zero? ? 'yeni yüzey yok' : "#{created} yüzey oluşturuldu")
      end
      if merge
        parts << (merged.zero? ? 'iç bölücü yüzey yok' : "#{merged} iç yüzey silindi")
      end
      if clean
        parts << (removed.zero? ? 'silinecek çizgi yok' : "#{removed} çizgi silindi")
      end
      text = parts.join(', ')
      text.empty? ? '' : "#{text[0].upcase}#{text[1..-1]}."
    end

    # --- Teşhis -------------------------------------------------------------

    def context_label(entity)
      parent = entity.parent
      return 'Model kökü' if parent.is_a?(Sketchup::Model)
      kind = parent.group? ? 'Grup' : 'Bileşen'
      name = parent.name.to_s
      name = '(isimsiz)' if name.empty?
      "#{kind} tanımı \"#{name}\""
    end

    def num(value)
      format('%.3f', value)
    end

    def describe_face(face, index)
      normal = face.normal
      material = face.material ? face.material.display_name : 'yok'
      "  [#{index}] normal=(#{num(normal.x)}, #{num(normal.y)}, #{num(normal.z)})" \
        "  alan=#{format('%.1f', face.area)}" \
        "  malzeme=#{material}" \
        "  tag=#{face.layer.name}" \
        "  bağlam=#{context_label(face)}"
    end

    def diagnose_edge(edge)
      lines = []
      lines << '=== ÇİZGİ TEŞHİSİ ==='
      lines << "Çizginin bağlamı: #{context_label(edge)}"
      lines << "Uzunluk: #{format('%.3f', edge.length.to_f)}"

      faces = edge.faces
      lines << "Bu çizgiye bağlı yüzey sayısı: #{faces.size}"
      lines << ''

      faces.each_with_index { |face, i| lines << describe_face(face, i + 1) }
      lines << ''

      if faces.size >= 2
        lines << 'Yüzey çiftleri:'
        faces.each_with_index do |face_a, i|
          ((i + 1)...faces.size).each do |j|
            face_b = faces[j]
            same_dir = face_a.normal.samedirection?(face_b.normal)
            on_plane = same_plane?(face_a, face_b)
            verdict =
              if same_dir && on_plane
                'EŞ DÜZLEMLİ'
              elsif on_plane
                'aynı düzlem ama TERS YÖN'
              else
                'farklı düzlem'
              end
            lines << "  #{i + 1}-#{j + 1}: aynı yön=#{same_dir ? 'evet' : 'hayır'}, " \
                     "aynı düzlem=#{on_plane ? 'evet' : 'hayır'}  -> #{verdict}"
          end
        end
        lines << ''
      end

      lines << '--- Kenar temizliği ---'
      if faces.empty?
        lines << 'Hiçbir yüzeye bağlı değil. "Boştaki Çizgileri de Sil" ayarı gerekir.'
      elsif faces.size == 1
        lines << 'Tek yüzeye bağlı (serbest kenar). Silinmez.'
      elsif faces.size == 2
        if faces[0].entityID == faces[1].entityID
          lines << 'İki tarafı da AYNI yüzey. Silinmez.'
        elsif !coplanar?(faces[0], faces[1])
          lines << 'İki yüzey eş düzlemli değil (ya da ters yönde). Silinmez.'
        elsif !mergeable?(faces[0], faces[1])
          lines << 'Malzeme/tag farklı. "Malzeme / Tag Farkını Koru" ayarını kapatınca silinir.'
        else
          lines << 'UYGUN: bu çizgi "Gereksiz Çizgileri Temizle" ile silinmeli.'
        end
      else
        lines << "Çizginin #{faces.size} yüzeyi var (2 değil). Salt kenar temizliği " \
                 'yetmez; önce aradaki iç bölücü yüzeyin silinmesi gerekir.'
      end

      if faces.size >= 3
        lines << ''
        lines << '--- İç bölücü testi (her yüzey için) ---'
        faces.each_with_index do |face, i|
          reason = partition_reason(face)
          if reason.nil?
            lines << "  [#{i + 1}] UYGUN -> \"Bitişik Hacimleri Birleştir\" bunu silmeli."
          else
            lines << "  [#{i + 1}] olmaz: #{reason}"
          end
        end
      end

      lines
    end

    def diagnose
      model = Sketchup.active_model
      return if model.nil?

      selection = model.selection
      lines = []

      containers = selection.select do |entity|
        entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)
      end

      unless containers.empty?
        lines << "DİKKAT: seçimde #{containers.size} grup/bileşen var."
        lines << 'Farklı grup/bileşenlerin içindeki geometri birbirine kaynaşmaz;'
        lines << 'aralarındaki çizgiler hiçbir eklentiyle silinemez. Önce Explode gerekir.'
        lines << ''
      end

      edges = selection.grep(Sketchup::Edge)

      if edges.empty?
        if containers.empty?
          lines << 'Teşhis için TEK BİR ÇİZGİ seçin.'
          lines << 'Geometri bir grubun içindeyse önce çift tıklayıp içine girin.'
        end
      else
        # Rastgele ilk çizgi yerine incelemeye değer olanı seç.
        target = edges.find { |edge| suspect?(edge) }

        if edges.size > 1
          if target
            lines << "Seçimde #{edges.size} çizgi var; şüpheli olan ilki inceleniyor."
          else
            lines << "Seçimde #{edges.size} çizgi var, hiçbiri şüpheli değil."
            lines << 'Hepsi ya gerçek köşe ya serbest kenar. İlki inceleniyor.'
            lines << 'Toplu döküm için "Teşhis: Kalan Çizgi Raporu" komutunu kullan.'
          end
          lines << ''
        end

        lines.concat(diagnose_edge(target || edges.first))
      end

      text = lines.join("\n")
      puts text
      puts ''
      UI.messagebox(text)
    end

    # --- Seçili çizgileri zorla birleştir -----------------------------------

    # Kullanıcı hangi çizgilerin gideceğini kendi seçer. Her çizgi için,
    # eş düzlemli yüzey çiftinin ARASINDA kalan yüzey önce silinir, sonra
    # çizgi silinir. Delete tuşuna basmaktan farkı bu sıra: Delete çizgiyi
    # silince aradaki yüzeyin sınırı da bozulur ve komşu geometri dağılır.
    def force_merge_selection
      model = Sketchup.active_model
      return if model.nil?

      selection = model.selection
      edges = unique(selection.grep(Sketchup::Edge))

      if edges.empty?
        UI.messagebox(
          "Önce yok etmek istediğin ÇİZGİLERİ seç.\n\n" +
          'Geometri bir grubun içindeyse önce çift tıklayıp içine gir.'
        )
        return
      end

      targets = []
      skipped = Hash.new(0)

      edges.each do |edge|
        next unless edge.valid?
        faces = edge.faces

        if faces.size < 2
          skipped["yalnızca #{faces.size} yüzeyi var"] += 1
          next
        end

        pair = coplanar_pair(faces)

        if pair.nil?
          skipped['gerçek köşe - yüzeyleri eş düzlemli değil'] += 1
          next
        end

        between = between_faces(edge)

        if between.size > 1
          skipped["#{faces.size} yüzey - arada tek yüzey yok, belirsiz"] += 1
          next
        end

        targets << [edge, between.first]
      end

      if targets.empty?
        lines = ['Seçilen çizgilerin hiçbiri birleştirilemedi.', '']
        skipped.each { |reason, count| lines << row(reason, count) }
        UI.messagebox(lines.join("\n"))
        return
      end

      faces_to_erase = unique(targets.map { |_, face| face }.compact)

      question = ["#{targets.size} çizgi yok edilecek."]
      unless faces_to_erase.empty?
        area = faces_to_erase.inject(0.0) { |sum, face| sum + face.area }
        question << "Bunun için #{faces_to_erase.size} adet aradaki yüzey silinecek " \
                    "(toplam alan #{format('%.0f', area)})."
      end
      unless skipped.empty?
        question << ''
        question << 'Atlananlar:'
        skipped.each { |reason, count| question << row(reason, count) }
      end
      question << ''
      question << 'Devam edilsin mi?'

      return unless UI.messagebox(question.join("\n"), MB_YESNO) == IDYES

      merged  = 0
      removed = 0

      model.start_operation('Seçili Çizgileri Birleştir', true)
      begin
        merged = erase_grouped(faces_to_erase)

        # Aradaki yüzey gittikten sonra çizginin 2 eş düzlemli yüzeyi kalmalı.
        ready = targets.map { |edge, _| edge }.select do |edge|
          next false unless edge.valid?
          faces = edge.faces
          faces.size == 2 &&
            faces[0].entityID != faces[1].entityID &&
            coplanar?(faces[0], faces[1])
        end

        removed = erase_grouped(ready)
        model.commit_operation
      rescue StandardError => error
        model.abort_operation
        Sketchup.status_text = ''
        UI.messagebox("İşlem sırasında hata oluştu:\n#{error.message}")
        return
      end

      Sketchup.status_text =
        "#{removed} çizgi ve #{merged} aradaki yüzey silindi."
    end

    # --- Toplu teşhis: kalan çizgiler ---------------------------------------

    def context_key(entity)
      parent = entity.parent
      parent.is_a?(Sketchup::Model) ? :model : parent.entityID
    end

    # Bir çizgi neden duruyor? Tek kelimelik kategori.
    def classify(edge)
      faces = edge.faces

      case faces.size
      when 0
        :no_face
      when 1
        :one_face
      when 2
        face_a = faces[0]
        face_b = faces[1]
        if face_a.entityID == face_b.entityID
          :same_face
        elsif coplanar?(face_a, face_b)
          mergeable?(face_a, face_b) ? :deletable : :material
        elsif same_plane?(face_a, face_b)
          :reversed
        else
          :corner
        end
      else
        :multi
      end
    end

    # Bir çizginin eş düzlemli yüzey çiftine DAHİL OLMAYAN yüzeyleri.
    # Yani sürekli yüzeyi bölen "aradaki" yüzey adayları.
    def between_faces(edge)
      faces = edge.faces
      pair = coplanar_pair(faces)
      return [] if pair.nil?
      keep = [pair[0].entityID, pair[1].entityID]
      faces.reject { |face| keep.include?(face.entityID) }
    end

    # İncelemeye değer, yani "silinmeliydi ama silinmedi" adayları.
    SUSPECT_CATEGORIES = [:deletable, :material, :reversed, :multi].freeze

    def suspect?(edge)
      SUSPECT_CATEGORIES.include?(classify(edge))
    end

    # Her çizgiyi kategorisine ayırıp sayar.
    def analyze(edges)
      stats    = Hash.new(0)
      reasons  = Hash.new(0)
      contexts = {}
      suspects = []

      edges.each do |edge|
        next unless edge.valid?
        contexts[context_key(edge)] = context_label(edge)

        category = classify(edge)
        stats[category] += 1
        suspects << edge if SUSPECT_CATEGORIES.include?(category)

        next unless category == :multi

        # Sadece ARADAKİ yüzeyleri say; eş düzlemli çiftin kendisini değil.
        candidates = between_faces(edge)

        if candidates.empty?
          reasons['çizginin yüzeyleri arasında eş düzlemli çift yok'] += 1
          next
        end

        candidates.each do |face|
          reason = partition_reason(face)
          key = reason.nil? ? 'UYGUN - iç bölücü sayılıyor' : reason.sub(/\Akenar \d+: /, '')
          reasons[key] += 1
        end
      end

      [stats, reasons, contexts, suspects]
    end

    def row(label, count, note = nil)
      line = "  #{label.ljust(42, '.')} #{count.to_s.rjust(6)}"
      line += "   #{note}" if note
      line
    end

    def report_lines(edges, stats, reasons, contexts)
      lines = []
      lines << '=== KALAN ÇİZGİ RAPORU ==='
      lines << "İncelenen çizgi sayısı: #{edges.size}"
      lines << "Bulunduğu bağlam sayısı: #{contexts.size}"
      contexts.each_value { |label| lines << "   - #{label}" }
      if contexts.size > 1
        lines << '   (!) Farklı grup/bileşenlerdeki geometri birbirine KAYNAŞMAZ.'
        lines << '       Aralarındaki çizgiler hiçbir şekilde silinemez; Explode gerekir.'
      end
      lines << ''
      lines << 'Çizgiler neden duruyor:'
      lines << row('Gerçek köşe (farklı düzlem)', stats[:corner], '-> normal, kalmalı')
      lines << row('Serbest kenar (tek yüzey)', stats[:one_face])
      lines << row('Yüzeysiz (boşta)', stats[:no_face], '-> "Boştaki Çizgileri de Sil"')
      lines << row('İki tarafı da aynı yüzey', stats[:same_face])
      lines << row('Aynı düzlem ama TERS YÖN', stats[:reversed], '-> Orient Faces')
      lines << row('Eş düzlemli, malzeme/tag farklı', stats[:material], '-> ayarı kapat')
      lines << row('Silinmeliydi (eş düzlemli, uygun)', stats[:deletable], '-> temizliği çalıştır')
      lines << row('3+ yüzeyli (arada iç bölücü var)', stats[:multi], '-> birleştirme gerekir')

      unless reasons.empty?
        lines << ''
        lines << '3+ yüzeyli çizgilerdeki yüzeyler, iç bölücü testini nerede kaybediyor:'
        reasons.sort_by { |_, count| -count }.each do |reason, count|
          text = reason.length > 42 ? reason[0, 39] + '...' : reason
          lines << row(text, count)
        end
      end

      lines
    end

    def report_edges
      model = Sketchup.active_model
      return if model.nil?

      selection = model.selection
      edges = unique(collect_edges(resolve_source(model, :auto), deep?))

      if edges.empty?
        UI.messagebox('İncelenecek çizgi bulunamadı.')
        return
      end

      Sketchup.status_text = 'Çizgiler inceleniyor...'
      stats, reasons, contexts, suspects = analyze(edges)
      Sketchup.status_text = ''

      lines = report_lines(edges, stats, reasons, contexts)
      text = lines.join("\n")
      puts text
      puts ''

      if suspects.empty?
        UI.messagebox(text)
        return
      end

      active     = model.active_entities
      selectable = suspects.select { |edge| edge.valid? && edge.parent == active.parent }

      if selectable.empty?
        UI.messagebox(text + "\n\n#{suspects.size} şüpheli çizgi var ama hepsi " \
                             'grup/bileşen içinde; buradan seçilemez.')
        return
      end

      question = text + "\n\n#{selectable.size} şüpheli çizgi seçilsin mi?" \
                        "\n\n(!) DELETE TUŞUNA BASMA. Bu çizgilerin ikiden fazla" \
                        "\nyüzeyi var; doğrudan silmek komşu yüzeyleri de bozar." \
                        "\nSeçtikten sonra \"Seçili Çizgileri Birleştir\" komutunu" \
                        "\nkullan - aradaki yüzeyi önce o siler, sonra çizgiyi."

      if UI.messagebox(question, MB_YESNO) == IDYES
        selection.clear
        selection.add(selectable)
        Sketchup.status_text =
          "#{selectable.size} çizgi seçildi - Delete değil, \"Seçili Çizgileri Birleştir\" kullan."
      end
    end

    # --- Arayüz -------------------------------------------------------------

    def icon(name, size)
      path = File.join(ICONS_DIR, "#{name}_#{size}.png")
      File.exist?(path) ? path : nil
    end

    def build_command(name, tooltip, status, icon_name, &block)
      command = UI::Command.new(name, &block)
      command.tooltip         = tooltip
      command.status_bar_text = status
      command.menu_text       = name
      if icon_name
        small = icon(icon_name, 16)
        large = icon(icon_name, 24)
        command.small_icon = small if small
        command.large_icon = large if large
      end
      command
    end

    def toggle_command(name, status, getter, setter)
      command = UI::Command.new(name) { send(setter, !send(getter)) }
      command.tooltip         = name
      command.status_bar_text = status
      command.set_validation_proc { send(getter) ? MF_CHECKED : MF_UNCHECKED }
      command
    end

    def needs_selection(command)
      command.set_validation_proc do
        model = Sketchup.active_model
        (model.nil? || model.selection.empty?) ? MF_GRAYED : MF_ENABLED
      end
      command
    end

    def create_commands
      faces_sel = build_command(
        'Seçimden Yüzey Oluştur',
        'Seçimden Yüzey Oluştur',
        'Seçili kenarlardan kapalı ve düzlemsel döngüler için yüzey oluşturur.',
        'makefaces'
      ) { perform('Yüzey Oluştur', :selection, true, false) }
      needs_selection(faces_sel)

      faces_all = build_command(
        'Aktif Bağlamın Tamamında',
        'Aktif Bağlamın Tamamında Yüzey Oluştur',
        'Aktif çizim bağlamındaki tüm kenarlardan yüzey oluşturur.',
        'makefaces_all'
      ) { perform('Yüzey Oluştur', :context, true, false) }

      cleanup = build_command(
        'Gereksiz Çizgileri Temizle',
        'Gereksiz Çizgileri Temizle',
        'Aynı düzlemdeki yüzeyleri bölen ayırıcı çizgileri siler. Seçim yoksa aktif bağlamın tamamında çalışır.',
        'cleanup'
      ) { perform('Gereksiz Çizgileri Temizle', :auto, false, true) }

      merge_cmd = build_command(
        'Bitişik Hacimleri Birleştir',
        'Bitişik Hacimleri Birleştir',
        'Ayrı ayrı push/pull yapılmış bitişik parçaların arasındaki iç bölücü yüzeyleri siler ve kalan gereksiz çizgileri temizler.',
        'merge'
      ) { perform('Bitişik Hacimleri Birleştir', :auto, false, true, true) }

      force_cmd = build_command(
        'Seçili Çizgileri Birleştir',
        'Seçili Çizgileri Birleştir',
        'Seçtiğin çizgileri yok eder: önce aradaki yüzeyi siler, sonra çizgiyi. Delete tuşundan farkı bu sıradır.',
        'force'
      ) { force_merge_selection }
      needs_selection(force_cmd)

      combo = build_command(
        'Yüzey Oluştur + Temizle',
        'Yüzey Oluştur + Temizle',
        'Önce yüzeyleri oluşturur, sonra gereksiz ayırıcı çizgileri siler. Seçim yoksa aktif bağlamın tamamında çalışır.',
        'combo'
      ) { perform('Yüzey Oluştur + Temizle', :auto, true, true) }

      deep_cmd = toggle_command(
        'Grup / Bileşen İçine Gir',
        'Açıkken grup ve bileşenlerin içindeki kenarlar da işlenir.',
        :deep?, :deep=
      )

      strict_cmd = toggle_command(
        'Malzeme / Tag Farkını Koru',
        'Açıkken farklı malzeme veya tag taşıyan yüzeyler birleştirilmez.',
        :strict?, :strict=
      )

      strays_cmd = toggle_command(
        'Boştaki Çizgileri de Sil',
        'Açıkken hiçbir yüzeye ait olmayan, tek başına kalmış çizgiler de silinir.',
        :strays?, :strays=
      )

      select_cmd = toggle_command(
        'Yeni Yüzeyleri Seç',
        'Açıkken işlem sonunda oluşturulan yüzeyler seçili hale gelir.',
        :select_new?, :select_new=
      )

      diagnose_cmd = build_command(
        'Teşhis: Seçili Çizgi',
        'Teşhis: Seçili Çizgi',
        'Seçili çizginin neden silinmediğini raporlar. Rapor Ruby Console\'a da yazılır.',
        nil
      ) { diagnose }

      report_cmd = build_command(
        'Teşhis: Kalan Çizgi Raporu',
        'Teşhis: Kalan Çizgi Raporu',
        'Tüm çizgileri "neden duruyor" kategorilerine ayırıp sayar. Rapor Ruby Console\'a da yazılır.',
        nil
      ) { report_edges }

      {
        :faces_sel => faces_sel,
        :faces_all => faces_all,
        :cleanup   => cleanup,
        :merge     => merge_cmd,
        :force     => force_cmd,
        :combo     => combo,
        :diagnose  => diagnose_cmd,
        :report    => report_cmd,
        :toggles   => [deep_cmd, strict_cmd, strays_cmd, select_cmd]
      }
    end

    def install_ui
      commands = create_commands

      menu = UI.menu('Plugins').add_submenu(PLUGIN_NAME)
      menu.add_item(commands[:faces_sel])
      menu.add_item(commands[:faces_all])
      menu.add_separator
      menu.add_item(commands[:cleanup])
      menu.add_item(commands[:merge])
      menu.add_item(commands[:force])
      menu.add_item(commands[:combo])
      menu.add_separator
      commands[:toggles].each { |command| menu.add_item(command) }
      menu.add_separator
      menu.add_item(commands[:report])
      menu.add_item(commands[:diagnose])

      toolbar = UI::Toolbar.new('Yüzey Oluştur')
      toolbar.add_item(commands[:faces_sel])
      toolbar.add_item(commands[:faces_all])
      toolbar.add_separator
      toolbar.add_item(commands[:cleanup])
      toolbar.add_item(commands[:merge])
      toolbar.add_item(commands[:force])
      toolbar.add_item(commands[:combo])
      toolbar.restore

      UI.add_context_menu_handler do |context_menu|
        model = Sketchup.active_model
        next if model.nil? || model.selection.empty?
        context_menu.add_separator
        context_menu.add_item('Yüzey Oluştur') do
          perform('Yüzey Oluştur', :selection, true, false)
        end
        context_menu.add_item('Gereksiz Çizgileri Temizle') do
          perform('Gereksiz Çizgileri Temizle', :selection, false, true)
        end
        context_menu.add_item('Bitişik Hacimleri Birleştir') do
          perform('Bitişik Hacimleri Birleştir', :selection, false, true, true)
        end
        context_menu.add_item('Seçili Çizgileri Birleştir') { force_merge_selection }
        context_menu.add_item('Teşhis: Seçili Çizgi') { diagnose }
      end
    end

  end # class << self

  unless file_loaded?(__FILE__)
    install_ui
    file_loaded(__FILE__)
  end

end
