# name: Topic Metadata
# about:
# version: 0.1
# authors: 
enabled_site_setting :topic_metadata_external_website
after_initialize do
  PostsController.class_eval do
    def create
      @manager_params = create_params
      @manager_params[:first_post_checks] = !is_api?
      manager = NewPostManager.new(current_user, @manager_params)
      if is_api?
        memoized_payload = DistributedMemoizer.memoize(signature_for(@manager_params), 120) do
          result = manager.perform
          MultiJson.dump(serialize_data(result, NewPostResultSerializer, root: false))
        end
        parsed_payload = JSON.parse(memoized_payload)
        backwards_compatible_json(parsed_payload, parsed_payload['success'])
      else
        result = manager.perform
        json = serialize_data(result, NewPostResultSerializer, root: false)
        backwards_compatible_json(json, result.success?)
      end
      status = result.success?
      unless status == false
        topicid =    result.post.topic_id  
        projectid = params[:projectidc]
        metadata = params[:metadatac]
        unless projectid.nil?
          begin
            url = SiteSetting.topic_metadata_external_website.gsub('{projectid}', projectid)
            connection = Excon.new(url)
            response = connection.request(expects: [200, 201], method: :Get)
          rescue
          end
        end
        unless metadata.nil?
          topicmetadata =  metadata.split(',')
          objArray = Array.new
          topicmetadata.each do |object|
            singledata = object.split(':')
            tempMetaRec = TopicCustomField.find_by(name: 'custom_metadata', topic_id:topicid)
            if(tempMetaRec.nil?)
              metaHash = Hash[singledata[0], singledata[1]] 
              metaJson = metaHash.to_json
              metaStr  = metaJson.to_s
              TopicCustomField.create(name: "custom_metadata",value: metaStr , topic_id:topicid)
            else
              tempMetaValue =  JSON.parse (tempMetaRec.value)
              tempMetaValue[singledata[0] ]=  singledata[1]
              tempMetaRec.value = tempMetaValue.to_json.to_s
              tempMetaRec.save       
            end                
          end
        end
      end
    end
  end
  module ::CustomTopicMetaData
        class Engine < ::Rails::Engine
            engine_name "custom_topic_metadata"
          isolate_namespace CustomTopicMetaData
      end
  end
  class CustomTopicMetaData::TopicmetadataController < Admin::AdminController
      def set_metadata
        topicdata = params[:data]
        topicid = params[:topic_id]
        topicRec = Topic.find_by_id(topicid)
        unless topicRec.nil?
          topicmetadata =  params[:data].split(',')
          objArray = Array.new
          topicmetadata.each do |object|
            singledata = object.split(':')
            tempMetaRec = TopicCustomField.find_by(name: 'custom_metadata', topic_id:params[:topic_id])
            if(tempMetaRec.nil?)
              metaHash = Hash[singledata[0], singledata[1]] 
              metaJson = metaHash.to_json
              metaStr  = metaJson.to_s
              TopicCustomField.create(name: "custom_metadata",value: metaStr , topic_id:params[:topic_id])
            else
              tempMetaValue =  JSON.parse (tempMetaRec.value)
              tempMetaValue[singledata[0] ]=  singledata[1]
              tempMetaRec.value = tempMetaValue.to_json.to_s
              tempMetaRec.save       
            end                
            
          end
        end
         render :json =>params[:data], :status => 200
      end
     def search_metadata
        topicmetadata =  params[:data].split(',')
        searchtype = params[:searchtype]
        query_chain = TopicCustomField.where(name:"custom_metadata")
        searchArr = Array.new
        topicmetadata.each do |object|
          singledata = object.split(':')
          query_chain = query_chain.where("value::jsonb->>'"+singledata[0]+"' = ?", singledata[1])
        end
        objArray = Array.new
        query_chain.each do |object|
         objArray << object.topic_id
        end
       render :json =>objArray.to_json, :status => 200
     end
     def view_metadata
        topic_id =  params[:id]
        topicMetadataQuery =  TopicCustomField.where(name:"custom_metadata",topic_id:topic_id).first
        topicMetaData = ''
        unless topicMetadataQuery.nil?
          topicMetaData  = topicMetadataQuery.value
        end
        render :json => topicMetaData, :status => 200
     end
     def delete_metadata
        topic_id =  params[:id]
        key =  params[:key]
        output = "{}"
        topic_metadata =  TopicCustomField.find_by(name:"custom_metadata",topic_id:topic_id)
        unless topic_metadata.nil?
          metaJson = JSON.parse(topic_metadata.value)
          metaJson.delete(key)      
          topic_metadata.value = metaJson.to_json.to_s
          topic_metadata.save
          output = topic_metadata.value
        end
        render :json => output, :status => 200  
     end
 end
  CustomTopicMetaData::Engine.routes.draw do
      get '/topic_metadata_api/setmetadata/:topic_id/:data' => 'topicmetadata#set_metadata' 
      get '/topic_metadata_api/searchmetadata/:data' => 'topicmetadata#search_metadata' 
      get '/topic_metadata_api/viewmetadata/:id' => 'topicmetadata#view_metadata'
      get '/topic_metadata_api/deletemetadata/:id/:key' => 'topicmetadata#delete_metadata' 
  end
  Discourse::Application.routes.append do
      mount ::CustomTopicMetaData::Engine, at: "/"
    end
end