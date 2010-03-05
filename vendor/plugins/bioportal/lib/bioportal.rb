module BioPortal
  module Acts
    def self.included(mod)
      mod.extend(ClassMethods)
    end

    module ClassMethods
      def acts_as_bioportal(options = {}, &extension)
        options[:base_url]="http://rest.bioontology.org/bioportal/"

        has_one :bioportal_concept,:as=>:conceptable,:dependent=>:destroy
        before_save :save_changed_concept

        extend BioPortal::Acts::SingletonMethods
        include BioPortal::Acts::InstanceMethods        
      end
    end

    module SingletonMethods

    end

    module InstanceMethods
      
      require 'BioPortalResources'

      def concept options={}
        return nil if self.bioportal_concept.nil?
        return self.bioportal_concept.concept_details options        
      end

      def ontology_id
        return nil if self.bioportal_concept.nil?
        return self.bioportal_concept.ontology_id
      end

      def ontology_version_id
        return nil if self.bioportal_concept.nil?
        return self.bioportal_concept.ontology_version_id
      end

      def concept_uri
        return nil if self.bioportal_concept.nil?
        return self.bioportal_concept.concept_uri
      end

      def ontology_id= value
        check_concept
        self.bioportal_concept.ontology_id=value
      end

      def ontology_version_id= value
        check_concept
        self.bioportal_concept.ontology_version_id=value
      end

      def concept_uri= value
        check_concept
        self.bioportal_concept.concept_uri=value
      end

      private

      def check_concept
        self.bioportal_concept=BioportalConcept.new if self.bioportal_concept.nil?
      end

      def save_changed_concept
        self.bioportal_concept.save! if !self.bioportal_concept.nil? && self.bioportal_concept.changed?
      end

    end
  end
  

  module RestAPI
    require 'rubygems'
    require "rexml/document"
    require 'open-uri'
    require 'uri'
    require 'xml'

    $REST_URL = "http://rest.bioontology.org/bioportal"
    
    def get_concept ontology_version_id,concept_id,options={}

      options[:light]=(options[:light] && options[:light]!=0) ? 1 : 0
      
      concept_url="/concepts/%ID%?conceptid=%CONCEPT_ID%&"
      concept_url=concept_url.gsub("%ID%",ontology_version_id.to_s)
      concept_url=concept_url.gsub("%CONCEPT_ID%",URI.encode(concept_id))
      options.keys.each{|key| concept_url += "#{key.to_s}=#{URI.encode(options[key].to_s)}&"}
      concept_url=concept_url[0..-2]
      full_concept_path=$REST_URL+concept_url
      parser = XML::Parser.io(open(full_concept_path))
      doc = parser.parse
      
      results = error_check doc

      unless results.nil?
        return results
      end

      return process_concepts_xml(doc).merge({:ontology_version_id=>ontology_version_id})
    end

    def get_ontology_details ontology_version_id
      url=$REST_URL+"/ontologies/#{ontology_version_id}"
      parser = XML::Parser.io(open(url))
      doc = parser.parse
      
      results = error_check doc

      unless results.nil?
        return results
      end

      doc.find("/*/data/ontologyBean").each{ |element|
        return parse_ontology_bean_xml(element)
      }
      
    end

    def search query,options={}
      options[:pagesize] ||= 10
      options[:pagenum] ||= 0
      
      search_url="/search/%QUERY%?"
      options.keys.each {|key| search_url+="#{key.to_s}=#{URI.encode(options[key].to_s)}&"}
      search_url=search_url[0..-2] #chop of trailing &
      
      search_url=search_url.gsub("%QUERY%",URI.encode(query))
      full_search_path=$REST_URL+search_url
      parser = XML::Parser.io(open(full_search_path))
      doc = parser.parse

      results = error_check doc

      unless results.nil?
        return results
      end

      results = []
      doc.find("/*/data/page/contents/searchResultList/searchBean").each{ |element|
        results << parse_search_result(element)
      }

      pages = 1
      doc.find("/*/data/page").each{|element|
        pages = element.first.find(element.path + "/numPages").first.content
      }

      return results.uniq,pages

    end

    def get_ontology_versions
      uri=$REST_URL+"/ontologies"
      parser = XML::Parser.io(open(uri))
      doc = parser.parse

      ontologies = error_check doc

      unless ontologies.nil?
        return ontologies
      end

      return parse_ontologies_xml doc
    end    
       

    #options can include
    # - offset - the offet to start from
    # - limit - the maximum number of terms returns
    def get_concepts_for_ontology_version_id ontology_version_id,options={}
      options[:offset]||=0
      uri="/concepts/#{ontology_version_id}/all?"
      options.keys.each{|k|uri+="#{k}=#{URI.encode(options[k].to_s)}&"}
      uri=uri[0..-2]
      uri=$REST_URL + uri      
      parser = XML::Parser.io(open(uri))
      doc = parser.parse

      concepts = error_check doc
      unless concepts.nil?
        return concepts
      end

      concepts=[]
      doc.find("/*/data/list/classBean").each{ |element|
        concepts << process_concept_bean_xml(element)
      }
      return concepts
      
    end

    #options can include
    # - offset - the offet to start from
    # - limit - the maximum number of terms returns
    def get_concepts_for_virtual_ontology_id virtual_ontology_id,options={}
      uri="/virtual/ontology/#{virtual_ontology_id}/all?"
      options.keys.each{|k|uri+="#{k}=#{URI.encode(options[k])}&"}
      uri=uri[0..-2]
      uri=$REST_URL + uri
      
      doc = REXML::Document.new(open(uri))

      concepts = error_check doc
      unless concepts.nil?
        return concepts
      end

      concepts=[]
      #TODO: parse concept list (xml is different to single concept)
      return concepts

    end

    private

    def error_check(doc)
      response = nil
      error={}
      begin
        doc.elements.each("org.ncbo.stanford.bean.response.ErrorStatusBean"){ |element|
          error[:error] = true
          error[:shortMessage] = element.elements["shortMessage"].get_text.value.strip
          error[:longMessage] =element.elements["longMessage"].get_text.value.strip
          response = error
        }
      rescue
      end

      return response
    end

    def parse_search_result element
      search_item={}
      search_item[:ontology_display_label]=element.first.find(element.path+"/ontologyDisplayLabel").first.content rescue nil
      search_item[:ontology_version_id]=element.first.find(element.path+"/ontologyVersionId").first.content rescue nil
      search_item[:ontology_id]=element.first.find(element.path+"/ontologyId").first.content rescue nil
      search_item[:record_type]=element.first.find(element.path+"/recordType").first.content rescue nil
      search_item[:concept_id]=element.first.find(element.path+"/conceptId").first.content rescue nil
      search_item[:concept_id_short]=element.first.find(element.path+"/conceptIdShort").first.content rescue nil
      search_item[:preferred_name]=element.first.find(element.path+"/preferredName").first.content rescue nil
      search_item[:contents]=element.first.find(element.path+"/contents").first.content rescue nil
      return search_item
    end

    def process_concepts_xml doc
      doc.find("/*/data/classBean").each{ |element|
        return process_concept_bean_xml(element)
      }      
    end

    def parse_ontologies_xml doc
      ontologies=[]
      doc.find("/*/data/list/ontologyBean").each{ |element|
        ontologies << parse_ontology_bean_xml(element)
      }
      return ontologies
    end

    def process_concept_bean_xml element
      result = {}
      ["id","label","fullId","type"].each do |x|
        node = element.first.find("#{element.path}/#{x}")
        result[x.to_sym] = node.first.content unless node.first.nil?
      end
      result[:full_id]=result.delete(:fullId) #convert to ruby style

      childcount = element.first.find(element.path + "/relations/entry[string='ChildCount']/int")
      result[:child_count] = childcount.first.content.to_i unless childcount.first.nil?

      # get synonyms
      synonyms = element.first.find(element.path + "/synonyms/string")
      result[:synonyms] = []
      synonyms.each do |synonym|
        result[:synonyms] << synonym.content
      end

      definitions = element.first.find(element.path + "/definitions/string")
      result[:definitions] = []
      definitions.each do |definition|
        result[:definitions] << definition.content
      end

      if (element.path == "/success/data/classBean")
        result[:children]=process_concept_children(element)
        result[:parents]=process_concept_parents(element)
      end

      return result
    end

    def parse_ontology_bean_xml element
      result = {}
      ["id","urn","homepage","documentation","codingScheme","isView","ontologyId","displayLabel","description","abbreviation","format","versionNumber","contactName","contactEmail","statusId","isFoundry","dateCreated"].each do |x|
        node = element.first.find("#{element.path}/#{x}")
        result[x.to_sym] = node.first.content unless node.first.nil?
      end
      result[:label]=result.delete(:displayLabel)
      result[:ontology_id]=result.delete(:ontologyId)
      result[:version_number]=result.delete(:versionNumber)
      result[:contact_name]=result.delete(:contactName)
      result[:contact_email]=result.delete(:contactEmail)
      result[:status_id]=result.delete(:statusId)
      result[:is_foundry]=result.delete(:isFoundry)
      result[:date_created]=result.delete(:dateCreated)
      result[:is_view]=result.delete(:isView)
      result[:coding_scheme]=result.delete(:codingScheme)
      return result
    end

    def process_concept_parents element
      search = element.path + "/relations/entry[string='SuperClass']/list/classBean"
      results = element.first.find(search)
      result=[]
      unless results.empty?
        results.each do |child|
          result << process_concept_bean_xml(child)
        end
      end
      return result
    end

    def process_concept_children element
      search = element.path + "/relations/entry[string='SubClass']/list/classBean"
      results = element.first.find(search)
      result=[]
      unless results.empty?
        results.each do |child|
          result << process_concept_bean_xml(child)
        end
      end
      return result
    end
    
  end
    
end

