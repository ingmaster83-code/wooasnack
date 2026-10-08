require 'json'

module Jekyll
  module SnackText
    module_function

    AMBIG = {}

    def clean_tail(s)
      s.to_s.strip.sub(/[\s\)\]\}\>'"”’.,!?~·\-]+\z/, '')
    end

    def hangul_tail?(s)
      c = clean_tail(s)[-1]
      !c.nil? && c.ord >= 0xAC00 && c.ord <= 0xD7A3
    end

    def batchim?(s)
      c = clean_tail(s)[-1]
      return false if c.nil?
      o = c.ord
      return (o - 0xAC00) % 28 != 0 if o >= 0xAC00 && o <= 0xD7A3
      false
    end

    def josa(word, with_b, without_b)
      return "#{word}#{with_b}(#{without_b})" unless hangul_tail?(word)
      word.to_s + (batchim?(word) ? with_b : without_b)
    end

    def eun_neun(w); josa(w, '은', '는'); end
    def i_ga(w); josa(w, '이', '가'); end

    def sg_name(do_short, sg)
      AMBIG[sg] ? "#{do_short} #{sg}" : sg
    end

    def fmt(n)
      n.to_s.reverse.scan(/\d{1,3}/).join(',').reverse
    end

    def type_counts_text(groups, k = 4)
      groups.first(k).map { |g| "#{g['label']} #{g['count']}곳" }.join(', ')
    end
  end

  class SnackPageGenerator < Generator
    safe true
    priority :normal

    CAP = 120
    TYPE_ORDER = %w[bungeoppang hotteok toast goguma eomuk kkwabaegi hodu takoyaki hotdog mandu tteokbokki etc].freeze

    TYPE_META = {
      'bungeoppang' => { 'label' => '붕어빵', 'icon' => '🐟', 'about' => '붕어빵·잉어빵·국화빵·풀빵·계란빵처럼 상호에 반죽 구움 간식 이름이 들어간 가게입니다.' },
      'hotteok' => { 'label' => '호떡', 'icon' => '🥞', 'about' => '상호에 호떡이 들어간 가게입니다.' },
      'toast' => { 'label' => '토스트', 'icon' => '🥪', 'about' => '상호에 토스트가 들어간 가게입니다. 프랜차이즈 토스트 가게도 포함됩니다.' },
      'goguma' => { 'label' => '군고구마', 'icon' => '🍠', 'about' => '상호에 군고구마·고구마가 들어간 가게입니다.' },
      'eomuk' => { 'label' => '어묵·오뎅', 'icon' => '🍢', 'about' => '상호에 어묵·오뎅이 들어간 가게입니다.' },
      'kkwabaegi' => { 'label' => '꽈배기', 'icon' => '🥨', 'about' => '상호에 꽈배기가 들어간 가게입니다.' },
      'hodu' => { 'label' => '호두과자', 'icon' => '🌰', 'about' => '상호에 호두과자가 들어간 가게입니다.' },
      'takoyaki' => { 'label' => '타코야끼', 'icon' => '🐙', 'about' => '상호에 타코야끼가 들어간 가게입니다.' },
      'hotdog' => { 'label' => '핫도그', 'icon' => '🌭', 'about' => '상호에 핫도그가 들어간 가게입니다.' },
      'mandu' => { 'label' => '만두·찐빵', 'icon' => '🥟', 'about' => '상호에 만두·찐빵·호빵이 들어간 가게입니다.' },
      'tteokbokki' => { 'label' => '떡볶이', 'icon' => '🌶️', 'about' => '상호에 떡볶이가 들어간 가게입니다.' },
      'etc' => { 'label' => '닭꼬치·츄러스', 'icon' => '🍡', 'about' => '상호에 닭꼬치·츄러스·옥수수 등이 들어간 가게입니다.' }
    }.freeze

    def generate(site)
      items = []
      Dir.glob(File.join(site.source, '_rawdata', 'snk_*.json')).sort.each { |p| items.concat(load_json(p)) }
      dongs = load_json(File.join(site.source, '_rawdata', 'dongs.json'))
      return if items.empty? || dongs.empty?

      SnackText::AMBIG.clear
      (items.map { |i| [i['sigungu'], i['doShort']] } + dongs.map { |d| [d['sigungu'], d['do']] }).uniq
        .group_by { |sg, _| sg }.each { |sg, l| SnackText::AMBIG[sg] = true if l.map { |_, d| d }.uniq.size > 1 }

      by_dong = items.group_by { |i| [i['doShort'], i['sigungu'], i['dong']] }
      by_sg = items.group_by { |i| [i['doShort'], i['sigungu']] }
      dong_by_sg = dongs.group_by { |d| [d['do'], d['sigungu']] }
      do_list = (items.map { |i| i['doShort'] } + dongs.map { |d| d['do'] }).uniq.sort
      counts = { do: 0, sg: 0, dong: 0, tdong: 0, tsg: 0, tdo: 0, shop: 0 }

      do_list.each do |do_short|
        d_items = items.select { |i| i['doShort'] == do_short }
        sgs = (dong_by_sg.keys.select { |dd, _| dd == do_short }.map { |_, s| s } + by_sg.keys.select { |dd, _| dd == do_short }.map { |_, s| s }).uniq
        sg_rows = sgs.map do |sg|
          sg_slug = (dong_by_sg[[do_short, sg]]&.first || {})['sgSlug'] || (by_sg[[do_short, sg]]&.first || {})['sgSlug'] || sg.tr(' ', '-')
          { 'name' => sg, 'slug' => sg_slug, 'count' => (by_sg[[do_short, sg]] || []).size }
        end.sort_by { |h| [-h['count'], h['name']] }
        site.pages << SnackDoPage.new(site, do_short, d_items, sg_rows)
        counts[:do] += 1

        sgs.each do |sg|
          sg_items = by_sg[[do_short, sg]] || []
          sg_dongs = (dong_by_sg[[do_short, sg]] || [])
          sg_slug = sg_rows.find { |h| h['name'] == sg }['slug']
          site.pages << SnackSigunguPage.new(site, do_short, sg, sg_slug, sg_items, sg_dongs, by_dong)
          counts[:sg] += 1

          ordered = sg_dongs.sort_by { |d| d['dong'] }
          ordered.each_with_index do |d, idx|
            list = by_dong[[do_short, sg, d['dong']]] || []
            prev_d = ordered[(idx - 1) % ordered.size]
            next_d = ordered[(idx + 1) % ordered.size]
            site.pages << SnackDongPage.new(site, d, list, prev_d, next_d)
            counts[:dong] += 1
            list.group_by { |i| i['type'] }.each do |tk, l|
              site.pages << SnackTypeDongPage.new(site, tk, d, l)
              counts[:tdong] += 1
            end
          end

          sg_items.group_by { |i| i['type'] }.each do |tk, l|
            site.pages << SnackTypeSgPage.new(site, tk, do_short, sg, sg_slug, l, by_dong)
            counts[:tsg] += 1
          end

          # 점포 상세
          sg_items.group_by { |i| i['dong'] }.each do |dong, l|
            sorted = l.sort_by { |i| i['dongRank'] }
            name_cnt = Hash.new(0)
            sorted.each { |x| name_cnt[x['shopName']] += 1 }
            sorted.each { |x| x['dupName'] = name_cnt[x['shopName']] > 1 }
            sorted.each_with_index do |c, idx|
              ring = sorted.size > 1 ? (1..[4, sorted.size - 1].min).map { |k| sorted[(idx + k) % sorted.size] } : []
              site.pages << SnackShopPage.new(site, c, ring, dongs_lookup(dongs, do_short, sg, dong))
              counts[:shop] += 1
            end
          end
        end

        d_items.group_by { |i| i['type'] }.each do |tk, l|
          site.pages << SnackTypeDoPage.new(site, tk, do_short, l)
          counts[:tdo] += 1
        end
      end

      type_rows = TYPE_ORDER.select { |t| items.any? { |i| i['type'] == t } }.map do |t|
        l = items.select { |i| i['type'] == t }
        TYPE_META[t].merge('key' => t, 'count' => l.size, 'do_rows' => l.group_by { |i| i['doShort'] }.map { |d, ll| { 'name' => d, 'count' => ll.size } }.sort_by { |h| -h['count'] })
      end
      type_rows.each { |tr| site.pages << SnackTypePage.new(site, tr) }
      site.pages << SnackTypeIndexPage.new(site, type_rows)

      top_dongs = dongs.select { |d| d['shopCount'].to_i > 0 }.sort_by { |d| [-d['shopCount'], d['dong']] }.first(30)
      site.data['snack_stats'] = {
        'total' => items.size, 'total_fmt' => SnackText.fmt(items.size), 'dong_count' => dongs.size, 'dong_fmt' => SnackText.fmt(dongs.size),
        'types' => type_rows.map { |t| { 'key' => t['key'], 'label' => t['label'], 'icon' => t['icon'], 'count' => t['count'], 'count_fmt' => SnackText.fmt(t['count']) } },
        'do_counts' => do_list.map { |d| { 'name' => d, 'count' => items.count { |i| i['doShort'] == d } } },
        'top_dongs' => top_dongs.map { |d| { 'url' => "/region/#{d['do']}/#{d['sgSlug']}/#{d['dong']}/", 'label' => "#{d['do']} #{d['sigungu']} #{d['dong']}", 'count' => d['shopCount'] } }
      }
      Jekyll.logger.info 'SnackGenerator:', counts.map { |k, v| "#{k} #{v}" }.join(' / ')
    end

    private

    def dongs_lookup(dongs, do_short, sg, dong)
      @dong_index ||= dongs.each_with_object({}) { |d, h| h[[d['do'], d['sigungu'], d['dong']]] = d }
      @dong_index[[do_short, sg, dong]]
    end

    def load_json(path)
      JSON.parse(File.read(path, encoding: 'utf-8'))
    rescue => e
      Jekyll.logger.warn 'SnackGenerator:', "#{path} 로드 실패: #{e.message}"
      []
    end
  end

  class SnackBasePage < Page
    def setup(site, dir, layout)
      @site = site
      @base = site.source
      @dir = dir
      @name = 'index.html'
      process(@name)
      read_yaml(File.join(@base, '_layouts'), "#{layout}.html")
      data['layout'] = layout
    end

    def seo(title, desc)
      data['title'] = title
      data['description'] = desc[0, 155]
    end

    def make_faq(pairs)
      data['faq'] = pairs.map { |q, a| { 'q' => q, 'a' => a } }
    end

    def tmeta(key)
      SnackPageGenerator::TYPE_META[key] || {}
    end

    def groups_for(list)
      by_t = list.group_by { |i| i['type'] }
      SnackPageGenerator::TYPE_ORDER.select { |t| by_t[t] }.map do |t|
        l = by_t[t].sort_by { |i| i['shopName'] }
        tmeta(t).merge('key' => t, 'count' => l.size, 'items' => l.first(SnackPageGenerator::CAP))
      end
    end
  end

  class SnackDoPage < SnackBasePage
    def initialize(site, do_short, d_items, sg_rows)
      setup(site, "region/#{do_short}", 'do')
      data['doShort'] = do_short
      data['totalCount'] = d_items.size
      by_t = d_items.group_by { |i| i['type'] }
      data['typeList'] = SnackPageGenerator::TYPE_ORDER.select { |t| by_t[t] }.map { |t| tmeta(t).merge('key' => t, 'count' => by_t[t].size) }
      data['sigunguList'] = sg_rows
      seo("#{do_short} 붕어빵·호떡·토스트 겨울간식 가게 #{SnackText.fmt(d_items.size)}곳 - 시군구별",
          "#{do_short}의 붕어빵·호떡·토스트·어묵·꽈배기 등 겨울·길거리 간식 가게 #{SnackText.fmt(d_items.size)}곳을 시군구·동별로 찾아보세요. 주소와 전화번호를 공공데이터로 안내합니다.")
    end
  end

  class SnackSigunguPage < SnackBasePage
    def initialize(site, do_short, sg, sg_slug, sg_items, sg_dongs, by_dong)
      setup(site, "region/#{do_short}/#{sg_slug}", 'sigungu')
      data['doShort'] = do_short
      data['sigungu'] = sg
      data['sgSlug'] = sg_slug
      data['sgLabel'] = SnackText.sg_name(do_short, sg)
      data['totalCount'] = sg_items.size
      by_t = sg_items.group_by { |i| i['type'] }
      data['typeList'] = SnackPageGenerator::TYPE_ORDER.select { |t| by_t[t] }.map { |t| tmeta(t).merge('key' => t, 'count' => by_t[t].size) }
      data['dongList'] = sg_dongs.map { |d| { 'name' => d['dong'], 'count' => (by_dong[[do_short, sg, d['dong']]] || []).size } }
                                 .sort_by { |h| [-h['count'], h['name']] }
      brief = data['typeList'].first(4).map { |t| "#{t['label']} #{t['count']}곳" }.join(', ')
      data['summary'] = sg_items.empty? ? "#{do_short} #{sg}에는 공공 인허가 데이터에 등록된 겨울간식 가게가 아직 없습니다. 가까운 동네를 선택해 주변 가게를 확인하세요." :
                        "#{do_short} #{sg}에는 영업 중인 겨울·길거리 간식 가게가 #{sg_items.size}곳 등록되어 있습니다(#{brief}). 동네를 선택해 붕어빵·호떡·토스트 가게를 찾아보세요."
      seo("#{data['sgLabel']} 붕어빵·호떡·토스트 가게 #{sg_items.size}곳 - 동네별 겨울간식",
          "#{do_short} #{sg}의 붕어빵·호떡·토스트·어묵·꽈배기 가게 #{sg_items.size}곳을 동별로 확인하세요. #{sg_dongs.size}개 동네별 근처 간식 가게와 주소·전화번호 안내.")
    end
  end

  class SnackDongPage < SnackBasePage
    def initialize(site, d, list, prev_d, next_d)
      do_short = d['do']; sg = d['sigungu']; dong = d['dong']
      setup(site, "region/#{do_short}/#{d['sgSlug']}/#{dong}", 'dong')
      sgn = SnackText.sg_name(do_short, sg)
      data['doShort'] = do_short
      data['sigungu'] = sg
      data['sgSlug'] = d['sgSlug']
      data['sgLabel'] = sgn
      data['dong'] = dong
      data['totalCount'] = list.size
      data['groups'] = groups_for(list)
      data['nearDongs'] = d['nearDongs'].first(8)
      data['nearShops'] = d['nearShops']
      data['prevDong'] = { 'dong' => prev_d['dong'] }
      data['nextDong'] = { 'dong' => next_d['dong'] }
      data['lat'] = d['lat']
      data['lng'] = d['lng']
      bung = list.count { |i| i['type'] == 'bungeoppang' }
      toast = list.count { |i| i['type'] == 'toast' }
      hot = list.count { |i| i['type'] == 'hotteok' }
      s = +''
      if list.empty?
        ns = d['nearShops'].first
        s << "공공 인허가 데이터에는 #{do_short} #{sg} #{dong}에 등록된 붕어빵·호떡·토스트 가게가 아직 없습니다."
        s << " 가장 가까운 곳은 #{ns['sigungu']} #{ns['dong']}의 #{ns['name']}(#{ns['type']}, 약 #{ns['km']}km)이고, 주변 #{d['nearShops'].size}곳을 아래에 모았습니다." if ns
      else
        s << "#{do_short} #{sg} #{dong}에는 영업 중인 겨울·길거리 간식 가게가 #{list.size}곳 등록되어 있습니다(#{SnackText.type_counts_text(data['groups'])})."
        s << (bung > 0 ? " 붕어빵·잉어빵 등을 상호로 내건 곳은 #{bung}곳입니다." : " 붕어빵을 상호로 내건 곳은 없고, 노점은 공공 데이터에 잡히지 않습니다.")
      end
      s << " 길거리 노점은 허가·단속 상황과 날씨에 따라 자리가 자주 바뀌므로 방문 전 확인이 필요합니다."
      data['summary'] = s
      if list.empty?
        seo("#{sgn} #{dong} 붕어빵·호떡·토스트 파는 곳 - 근처 겨울간식 가게",
            "#{do_short} #{sg} #{dong} 붕어빵·호떡·토스트 가게를 찾는다면? 이 동네에 등록된 가게는 없지만 #{d['nearShops'].empty? ? '이웃 동네 안내와 붕어빵 노점 찾는 요령' : "가까운 겨울간식 가게 #{d['nearShops'].size}곳과 이웃 동네"}를 알려드립니다.")
      else
        seo("#{sgn} #{dong} 붕어빵·호떡·토스트 - 겨울간식 가게 #{list.size}곳 (#{data['groups'].first(3).map { |g| g['label'] }.join('·')})",
            "#{do_short} #{sg} #{dong}의 붕어빵·호떡·토스트·어묵 등 겨울간식 가게 #{list.size}곳. #{SnackText.type_counts_text(data['groups'], 3)}. 주소·전화번호와 근처 동네 가게까지 한눈에.")
      end
      pairs = []
      pairs << ["#{dong}에 붕어빵 파는 곳이 있나요?",
                bung > 0 ? "공공 인허가 데이터 기준 #{do_short} #{sg} #{dong}에는 붕어빵·잉어빵·국화빵 등을 상호로 내건 가게가 #{bung}곳 등록되어 있습니다. 아래 목록에서 주소와 전화번호를 확인하세요." :
                           "공공 인허가 데이터에는 #{dong}에 붕어빵을 상호로 내건 가게가 없습니다. 붕어빵 노점은 대부분 인허가 목록에 잡히지 않으니 지도 앱에서 '#{dong} 붕어빵'을 검색하거나 근처 동네 목록을 확인하세요."]
      pairs << ["#{dong}에 토스트·호떡 가게도 있나요?", (toast + hot) > 0 ? "토스트 가게 #{toast}곳, 호떡 가게 #{hot}곳이 등록되어 있습니다." : "공공 인허가 데이터에는 #{dong}에 토스트·호떡을 상호로 내건 가게가 없습니다. 가까운 동네의 가게를 아래에서 확인할 수 있습니다."]
      pairs << ["붕어빵 노점은 왜 목록에 없나요?", "노점은 영업 허가 대상이 아니거나 무허가인 경우가 많아 인허가 데이터에 등록되지 않습니다. 이 사이트는 인허가 데이터에 있는 가게(상호에 붕어빵·호떡·토스트 등이 포함된 영업 중 점포)만 보여줍니다."]
      make_faq(pairs)
    end
  end

  class SnackTypeDongPage < SnackBasePage
    def initialize(site, tk, d, list)
      do_short = d['do']; sg = d['sigungu']; dong = d['dong']
      setup(site, "type/#{tk}/#{do_short}/#{d['sgSlug']}/#{dong}", 'type_list')
      m = tmeta(tk)
      sgn = SnackText.sg_name(do_short, sg)
      data['typeKey'] = tk
      data['typeLabel'] = m['label']
      data['typeIcon'] = m['icon']
      data['about'] = m['about']
      data['level'] = 'dong'
      data['doShort'] = do_short
      data['sigungu'] = sg
      data['sgSlug'] = d['sgSlug']
      data['sgLabel'] = sgn
      data['dong'] = dong
      data['totalCount'] = list.size
      data['items'] = list.sort_by { |i| i['shopName'] }.first(SnackPageGenerator::CAP)
      data['nearDongs'] = d['nearDongs'].first(8)
      data['summary'] = "#{do_short} #{sg} #{dong}에는 상호에 #{m['label']}이(가) 들어간 영업 중 가게가 #{list.size}곳 등록되어 있습니다. 주소와 전화번호를 확인하고, 방문 전에 영업 여부를 확인하세요."
      seo("#{sgn} #{dong} #{m['label']} 파는 곳 #{list.size}곳 - 주소·전화번호",
          "#{do_short} #{sg} #{dong}의 #{m['label']} 가게 #{list.size}곳 목록. 가게별 주소·전화번호·인허가일과 근처 동네 #{m['label']} 가게를 확인하세요.")
      make_faq([["#{dong} #{m['label']} 가게는 몇 곳인가요?", "공공 인허가 데이터 기준 #{do_short} #{sg} #{dong}에는 #{m['label']} 가게가 #{list.size}곳 등록되어 있습니다."],
                ["#{m['label']} 노점도 포함되어 있나요?", "아니요. 노점은 인허가 데이터에 등록되지 않는 경우가 많아 포함되지 않았습니다. 상호에 #{m['label']}이(가) 들어간 영업 점포만 보여줍니다."]])
    end
  end

  class SnackTypeSgPage < SnackBasePage
    def initialize(site, tk, do_short, sg, sg_slug, list, by_dong)
      setup(site, "type/#{tk}/#{do_short}/#{sg_slug}", 'type_list')
      m = tmeta(tk)
      sgn = SnackText.sg_name(do_short, sg)
      data['typeKey'] = tk
      data['typeLabel'] = m['label']
      data['typeIcon'] = m['icon']
      data['about'] = m['about']
      data['level'] = 'sg'
      data['doShort'] = do_short
      data['sigungu'] = sg
      data['sgSlug'] = sg_slug
      data['sgLabel'] = sgn
      data['totalCount'] = list.size
      data['items'] = list.sort_by { |i| [i['dong'], i['shopName']] }.first(SnackPageGenerator::CAP)
      data['dongList'] = list.group_by { |i| i['dong'] }.map { |dg, l| { 'name' => dg, 'count' => l.size } }.sort_by { |h| [-h['count'], h['name']] }
      top = data['dongList'].first(3).map { |h| h['name'] }.join('·')
      data['summary'] = "#{do_short} #{sg}에는 상호에 #{m['label']}이(가) 들어간 영업 중 가게가 #{list.size}곳 있습니다. #{top} 일대에 많습니다."
      seo("#{sgn} #{m['label']} 파는 곳 #{list.size}곳 - 동별 주소·전화번호",
          "#{do_short} #{sg}의 #{m['label']} 가게 #{list.size}곳을 동별로 확인하세요. 가게별 주소·전화번호·인허가일을 공공데이터로 안내합니다.")
      make_faq([["#{sg} #{m['label']} 가게는 몇 곳인가요?", "공공 인허가 데이터 기준 #{do_short} #{sg}에는 #{m['label']} 가게가 #{list.size}곳 등록되어 있습니다."]])
    end
  end

  class SnackTypeDoPage < SnackBasePage
    def initialize(site, tk, do_short, list)
      setup(site, "type/#{tk}/#{do_short}", 'type_do')
      m = tmeta(tk)
      data['typeKey'] = tk
      data['typeLabel'] = m['label']
      data['typeIcon'] = m['icon']
      data['about'] = m['about']
      data['doShort'] = do_short
      data['totalCount'] = list.size
      data['sigunguList'] = list.group_by { |i| i['sigungu'] }.map { |sg, l| { 'name' => sg, 'slug' => l.first['sgSlug'], 'count' => l.size } }.sort_by { |h| [-h['count'], h['name']] }
      data['summary'] = "#{do_short}에는 상호에 #{m['label']}이(가) 들어간 영업 중 가게가 #{list.size}곳 등록되어 있습니다. #{data['sigunguList'].first(3).map { |h| h['name'] }.join('·')} 일대에 많습니다."
      seo("#{do_short} #{m['label']} 파는 곳 #{list.size}곳 - 시군구별 목록",
          "#{do_short}의 #{m['label']} 가게 #{list.size}곳을 시군구별로 찾아보세요. 가게별 주소와 전화번호를 공공데이터로 안내합니다.")
    end
  end

  class SnackTypePage < SnackBasePage
    def initialize(site, tr)
      setup(site, "type/#{tr['key']}", 'type_page')
      data['typeKey'] = tr['key']
      data['typeLabel'] = tr['label']
      data['typeIcon'] = tr['icon']
      data['about'] = tr['about']
      data['totalCount'] = tr['count']
      data['doList'] = tr['do_rows']
      data['summary'] = "전국에 상호에 #{tr['label']}이(가) 들어간 영업 중 가게는 공공 인허가 데이터 기준 #{SnackText.fmt(tr['count'])}곳입니다. 시도를 선택해 동네별 #{tr['label']} 가게를 찾아보세요."
      seo("전국 #{tr['label']} 파는 곳 #{SnackText.fmt(tr['count'])}곳 - 지역별 주소·전화번호",
          "전국 #{tr['label']} 가게 #{SnackText.fmt(tr['count'])}곳을 시도·시군구·동별로 찾아보세요. 주소와 전화번호를 공공데이터로 안내합니다.")
    end
  end

  class SnackTypeIndexPage < SnackBasePage
    def initialize(site, type_rows)
      setup(site, 'type', 'type_index')
      data['typeList'] = type_rows
      seo('겨울간식 종류별 찾기 - 붕어빵·호떡·토스트·어묵·꽈배기', '붕어빵, 호떡, 토스트, 어묵, 꽈배기, 호두과자, 타코야끼, 핫도그, 만두·찐빵, 떡볶이 가게를 종류별로 찾아보세요.')
    end
  end

  class SnackShopPage < SnackBasePage
    def initialize(site, c, ring, dong_info)
      setup(site, "shop/#{c['slug']}", 'shop')
      data.merge!(c)
      addr = c['road'].to_s != '' ? c['road'] : c['lot']
      data['addr'] = addr
      dong_part = c['dong'] == '기타' ? '' : " #{c['dong']}"
      dl = c['dong'] == '기타' ? '기타 지역' : c['dong']
      sgn = SnackText.sg_name(c['doShort'], c['sigungu'])
      data['dongLabel'] = dl
      data['sgLabel'] = sgn
      data['near'] = c['near'].map { |x| x.merge('dist' => (x['m'] < 1000 ? "#{x['m']}m" : "약 #{(x['m'] / 1000.0).round(1)}km")) }
      data['ring'] = ring.map { |x| { 'slug' => x['slug'], 'name' => x['shopName'], 'type' => x['typeLabel'] } }
      data['nearDongs'] = dong_info ? dong_info['nearDongs'].first(6) : []
      py = c['permit'].to_s[0, 4].to_i
      data['permitYear'] = py > 1950 ? py : nil
      name = c['shopName']
      s = +"#{SnackText.eun_neun(name)} #{c['doShort']} #{c['sigungu']}#{dong_part}에 있는 #{c['typeLabel']} 가게입니다."
      s << " 상호에 #{c['typeLabels'].join('·')}이(가) 들어 있습니다." if c['typeLabels'].size > 1
      if py > 1950
        n = c['dongCount']; r = c['dongRank']
        s << " #{c['permit']}에 인허가를 받았고,"
        if n > 1
          rank_txt = r == 1 ? '가장 먼저 인허가를 받은 곳입니다.' : (r == n ? '가장 최근에 인허가를 받은 곳입니다.' : "인허가가 #{r}번째로 오래됐습니다.")
          s << " #{dl}의 겨울간식 가게 #{n}곳 중 #{rank_txt}"
        else
          s << " #{dl}에서 등록된 유일한 겨울간식 가게입니다."
        end
      end
      data['summary'] = s
      first_near = c['near'].first
      tel_txt = c['tel'].to_s != '' ? c['tel'] : nil
      road_hint = c['dupName'] ? " (#{addr.sub(/\s*\(.*\z/, '').split(' ').last(2).join(' ')})" : ''
      seo("#{name}#{road_hint} - #{sgn}#{dong_part} #{c['typeLabel']} 주소·전화번호",
          "#{c['doShort']} #{c['sigungu']}#{dong_part} #{c['typeLabel']} 가게 #{name}. 주소 #{addr}#{tel_txt ? ", 전화 #{tel_txt}" : ''}.#{first_near ? " 근처 #{first_near['name']}(#{first_near['m']}m) 등 간식 가게 안내." : ''}")
      pairs = []
      pairs << ["#{SnackText.eun_neun(name)} 어디에 있나요?", "주소는 #{addr}입니다. #{c['doShort']} #{c['sigungu']}#{dong_part}에 위치해 있습니다."]
      pairs << ["#{name} 전화번호는요?", tel_txt ? "공공데이터에 등록된 전화번호는 #{tel_txt}입니다. 영업시간과 메뉴는 전화로 먼저 확인하세요." : "공공데이터에 전화번호가 등록되어 있지 않습니다. 카카오맵 등 지도 앱에서 업장 정보를 확인하세요."]
      pairs << ["#{dl} 근처에 다른 #{c['typeLabel']} 가게가 있나요?", c['near'].empty? ? "반경 3km 안에 등록된 다른 겨울간식 가게가 없습니다." : "가까운 곳에 #{c['near'].first(3).map { |x| "#{x['name']}(#{x['m']}m)" }.join(', ')} 등이 있습니다."]
      make_faq(pairs)
    end
  end

  class SnackSitemapGenerator < Generator
    safe true
    priority :lowest
    CHUNK = 40_000

    def generate(site)
      urls = site.pages.reject { |p| p.url.to_s.end_with?('.json', '.xml', '.txt', '.js', '.css') || p.url.to_s == '/404.html' || p.data['sitemap'] == false }
                       .map { |p| p.url }.uniq
      base = site.config['url'].to_s
      chunks = urls.each_slice(CHUNK).to_a
      chunks.each_with_index do |c, idx|
        body = +"<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<urlset xmlns=\"http://www.sitemaps.org/schemas/sitemap/0.9\">\n"
        c.each { |u| body << "  <url><loc>#{base}#{u}</loc></url>\n" }
        body << "</urlset>\n"
        site.pages << raw_page(site, "sitemap-#{idx + 1}.xml", body)
      end
      index = +"<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<sitemapindex xmlns=\"http://www.sitemaps.org/schemas/sitemap/0.9\">\n"
      chunks.each_index { |idx| index << "  <sitemap><loc>#{base}/sitemap-#{idx + 1}.xml</loc></sitemap>\n" }
      index << "</sitemapindex>\n"
      site.pages << raw_page(site, 'sitemap.xml', index)
      Jekyll.logger.info 'SnackSitemap:', "#{urls.size}개 URL → #{chunks.size}개 사이트맵"
    end

    private

    def raw_page(site, name, content)
      pg = PageWithoutAFile.new(site, site.source, '', name)
      pg.content = content
      pg.data['layout'] = nil
      pg.data['sitemap'] = false
      pg
    end
  end
end
