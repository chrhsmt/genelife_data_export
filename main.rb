require 'ferrum'
require 'csv'
require 'debug'
require 'net/http'
require 'json'
require 'uri'

URL_BASE = 'https://hvyypnaecf.execute-api.ap-northeast-1.amazonaws.com/latest'

@browser = Ferrum::Browser.new(base_url: 'https://genesis2.genelife.jp', timeout: 60, headless: false)

def wait
  @browser.network.wait_for_idle(duration: 0.2, timeout: 2) rescue Ferrum::TimeoutError
end

def gene_cookie
  @gene_cookie ||= @browser.cookies.all['gene'].value
end

def get_by_json(params)
  uri = URI.parse("#{URL_BASE}?#{params}")
  json = Net::HTTP.get(uri)
  JSON.parse(json)
end

def extract_data(disease_all, access_token, kit_code)
  raise '疾患項目取得エラー' unless disease_all['status'] == 'ok'

  results = []
  disease_all['result'].each do |item|
    unit = item['unit']
    unit_name = unit['name']
    unit_id = unit['id']

    p unit_name

    unit_detail = get_by_json("token=#{access_token}&kit=#{kit_code}&f=detail&unit=#{unit_id}")

    raise "#{unit_name}取得エラー" unless unit_detail['status'] == 'ok'

    # 遺伝子マスタ情報
    unit_master = unit_detail['result']['unit']['descriptions'].map do |description|
      [
        description['gene_master']['ghnumber'], # 多型部位: ex: GH010323
        {
          gene_name: description['gene_name'], # snip名
          explanation: description['explanation'], # 説明
          evidence_rank: description['evidence_rank'], # 信頼性
        },
      ]
    end.to_h

    # 個人の結果
    unit_detail_results = unit_detail['result']['detail_genes']
    unit_detail_results.each do |result|
      p result['ghnumber']
      results << {
        unit_name: unit_name,
        ghnumber: result['ghnumber'], # 多型部位: ex: GH010323
        gene_name: unit_master[result['ghnumber']][:gene_name], # snip名
        value: result['value'], # snip: CC, GG
        explanation: unit_master[result['ghnumber']][:explanation], # 説明
        evidence_rank: unit_master[result['ghnumber']][:evidence_rank], # 信頼性
      }
    end
  end

  results
end

def main
  @result_data = []

  # 1. ログイン
  @browser.go_to('https://customer.genelife.jp')
  wait
  @browser.at_xpath('//*[@id="root"]/div/div/div/div/div[1]/div/div[2]/div[1]/div/ul/li[1]').click
  @browser.at_css("input[name='username']").focus.type(ENV['EMAIL'])
  @browser.at_css("input[name='password']").focus.type(ENV['PASSWORD'])
  @browser.at_xpath('//*[@id="root"]/div/div/div/div/div[1]/div/div[2]/div[1]/div/div[2]/div/div[7]/input').click
  wait

  info_json = get_by_json("f=info&gene=#{gene_cookie}")
  kit_code = info_json['kit_code']
  access_token = info_json['access_token']

  # 疾患項目全て
  p '-- 疾患項目取得 --'
  disease_all = get_by_json("token=#{access_token}&gender=male&kit=#{kit_code}&type=disease&f=summary")
  @result_data += extract_data(disease_all, access_token, kit_code)

  # 体質項目全て
  constitution_all = get_by_json("token=#{access_token}&gender=male&kit=#{kit_code}&type=constitution&f=summary")
  p '-- 体質項目取得 --'
  @result_data += extract_data(constitution_all, access_token, kit_code)

  # ファイルへ書き込み
  CSV.open('./snips.csv', 'wb') do |csv|
    csv << ['検査項目', 'ghnumber', 'gene_name', 'value', 'explanation', 'evidence_rank']
    @result_data.each do |result|
      csv << [
        result[:unit_name],
        result[:ghnumber],
        result[:gene_name],
        result[:value],
        result[:explanation],
        result[:evidence_rank],
      ]
    end
  end

  @browser.quit
end

main
