# coding: utf-8

require 'recastai'
require 'dotenv/load'
require 'pry'
require 'json'
require 'open-uri'


def bot(payload)
  connect = RecastAI::Connect.new(ENV['REQUEST_TOKEN'], ENV['LANGUAGE'])
  request = RecastAI::Request.new(ENV['REQUEST_TOKEN'])

  connect.handle_message(payload) do |message|
    response = request.converse_text(message.content, conversation_token: message.sender_id)

    if response.intent.slug == "reco_recette"
      url = 'http://localhost:3000/api/v1/suggest'
      suggest_serialized = open(url).read
      suggest = JSON.parse(suggest_serialized)


      contents = []
      suggest["recipes"].each do |recipe|
              contents << {
                title: "#{recipe["title"]}",
                imageUrl: "#{recipe["imageUrl"]}",
                buttons: [
                  {
                    title: 'Voir plus',
                    value: "http://localhost:3000#{recipe['recipeUrl']}",
                    type: 'web_url',
                  },
                  {
                    type: 'postback',
                    title: 'Faire cette recette',
                    value: 'SELECT_RECIPE'
                  }
                ]
              }
      end
      messages = [
        {
          type: 'carousel',
          content: contents,
        }
      ]
      connect.send_message(messages, message.conversation_id)
    else
      replies = response.replies.map{ |r| { type: 'text', content: r } }
      connect.send_message(replies, message.conversation_id)
    end

  end

  200
end
