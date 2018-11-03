# Description:
#   Allows creation of GLPI tickets and listens for GLPI ticket references, queries the GLPI API and retrieves details to post back to the Slack channel.
#
# Dependencies:
#    "hubot-env": "0.0.2",
#    "hubot-slack": ">=4.4.0",
#
# Configuration:
#   HUBOT_GLPI_HOST
#   HUBOT_GLPI_USER_TOKEN
#
# Commands:
#   <GLPI ticket URL> - Looks up and responds with information regarding the specified GLPI ticket
#   hubot ticket - Adds a new GLPI ticket with the Slack user as the requester. Uses first line of the message as the ticket title and all subsequent lines as the ticket description.
#
# Author:
#   Dave Jennings (@davejennings)

module.exports = (robot) ->

  https = require 'https'
  request = require 'request'
  dateFormat = require 'dateformat'
  glpi_host = process.env.HUBOT_GLPI_HOST
  user_token = process.env.HUBOT_GLPI_USER_TOKEN
  robot.hear /front\/ticket\.form.php\?id=(\d+)/i, (msg) ->
    # base64 encoded string of - username:password e.g. johnsmith:password123
    # 'Authorization': 'Basic abcdefghijklmnopqrstuvwxyz12'
    #
    # Or API token from user preferences - but bug with GLPI means you can't login with your regular credentials 
    # after you use this token once without resetting your account
    # 'Authorization': 'user_token qQk2aMg2fVGAlxieC0vYRHbLOYobMHmYBQ1caMPS'
    headersObj =
      'Content-Type': 'application/json'
      'Authorization': 'user_token ' + user_token

    options =
      host: glpi_host
      port: 443
      path: '/apirest.php/initSession/'
      headers: headersObj

    https.get options, (res) ->
      data = ""
      res.on 'data', (chunk) ->
        data += chunk.toString()
      res.on 'end', () ->
        sessionDetails = JSON.parse(data)
        headersObj =
          'Content-Type': 'application/json'
          'Session-Token': sessionDetails.session_token

        options =
          host: glpi_host
          port: 443
          path: "/apirest.php/Ticket/#{msg.match[1]}"
          headers: headersObj

        https.get options, (res) ->
          data = ""
          res.on 'data', (chunk) ->
            data += chunk.toString()
          res.on 'end', () ->
            ticketDetails = JSON.parse(data)
            options =
              host: glpi_host
              port: 443
              path: "/apirest.php/Ticket/" + ticketDetails.id + "/Ticket_User"
              headers: headersObj
        
            https.get options, (res) ->
              data = ""
              res.on 'data', (chunk) ->
                data += chunk.toString()
              res.on 'end', () ->
                userDetails = JSON.parse(data)
                reporter = ""
                assignee = ""
                for user of userDetails
                  if userDetails[user].type == 1
                    reporterID = userDetails[user].users_id
                  if userDetails[user].type == 2
                    assigneeID = userDetails[user].users_id

                options =
                  host: glpi_host
                  port: 443
                  path: "/apirest.php/User/" + reporterID
                  headers: headersObj

                https.get options, (res) ->
                  data = ""
                  res.on 'data', (chunk) ->
                    data += chunk.toString()
                  res.on 'end', () ->
                    reporterDetails = JSON.parse(data)

                    options =
                      host: glpi_host
                      port: 443
                      path: "/apirest.php/User/" + assigneeID
                      headers: headersObj

                    https.get options, (res) ->
                      data = ""
                      res.on 'data', (chunk) ->
                        data += chunk.toString()
                      res.on 'end', () ->
                        assigneeDetails = JSON.parse(data)

                        options =
                          host: glpi_host
                          port: 443
                          path: "/apirest.php/killSession/"
                          headers: headersObj

                        https.get options, (res) ->
                          dateReported = new Date(ticketDetails.date)
                          dueDate = new Date(ticketDetails.time_to_resolve)
                          attachment = 
                            attachments:[
                              title: ticketDetails.name
                              fallback: ticketDetails.name
                              title_link: 'https://' + glpi_host + '/front/ticket.form.php?id=' + ticketDetails.id
                              text: ticketDetails.content
                              fields:[
                                { title: "Reported By", value: reporterDetails.firstname + " " + reporterDetails.realname, short: "true" }
                                { title: "Date Reported", value: dateFormat(dateReported, "dd/mm/yyyy HH:MM"), short: "true" }
                                { title: "Assigned To", value: assigneeDetails.firstname + " " + assigneeDetails.realname, short: "true" }
                                { title: "Due Date", value: dateFormat(dueDate, "dd/mm/yyyy HH:MM"), short: "true" }
                              ]
                            ]

                          robot.send room: msg.envelope.room, attachment

  robot.respond /ticket (.+)\n+((.|\s)+)$/i, (msg) ->
    # base64 encoded string of - username:password e.g. johnsmith:password123
    # 'Authorization': 'Basic abcdefghijklmnopqrstuvwxyz12'
    #
    # Or API token from user preferences - but bug with GLPI means you can't login with your regular credentials 
    # after you use this token once without resetting your account
    # 'Authorization': 'user_token qQk2aMg2fVGAlxieC0vYRHbLOYobMHmYBQ1caMPS'
    headersObj =
      'Content-Type': 'application/json'
      'Authorization': 'user_token ' + user_token

    options =
      host: glpi_host
      port: 443
      path: '/apirest.php/initSession/'
      headers: headersObj

    https.get options, (res) ->
      data = ""
      res.on 'data', (chunk) ->
        data += chunk.toString()
      res.on 'end', () ->
        sessionDetails = JSON.parse(data)
        headersObj =
          'Content-Type': 'application/json'
          'Session-Token': sessionDetails.session_token

        options =
          host: glpi_host
          port: 443
          path: "/apirest.php/search/User?criteria[0][field]=5&criteria[0][searchtype]=contains&criteria[0][value]=#{msg.envelope.user.profile.email}&uid_cols=true&withindexes=true"
          headers: headersObj

        https.get options, (res) ->
          data = ""
          res.on 'data', (chunk) ->
            data += chunk.toString()
          res.on 'end', () ->
            userDetails = JSON.parse(data)
            if !userDetails.data
              msg.send "Ticket not created: GLPI user with email address \"#{msg.envelope.user.profile.email}\" not found."
              return
            userId = Object.keys(userDetails.data)

            postData = input: [ {
              'name': "#{msg.match[1]}"
              'content': "#{msg.match[2]}"
              'status': 1
              'urgency': 3
              'impact': 3
              'priority': 1
              '_users_id_requester': userId[0]
              'requesttypes_id': 6
            } ]

            postHeadersObj =
              'Content-Type': 'multipart/form-data'
              'Session-Token': sessionDetails.session_token

            options =
              uri: "https://" + glpi_host + "/apirest.php/Ticket"
              port: 443
              method: 'POST'
              headers: postHeadersObj
              form: postData

            request options, (err, res, body) ->
              if err
                console.log(err)

              newTicket = JSON.parse(body)

              options =
                host: glpi_host
                port: 443
                path: "/apirest.php/Ticket/" + newTicket[0].id + "/Ticket_User"
                headers: headersObj

              https.get options, (res) ->
                data = ""
                res.on 'data', (chunk) ->
                  data += chunk.toString()
                res.on 'end', () ->
                  userDetails = JSON.parse(data)
                  for user of userDetails
                    if userDetails[user].type == 2
                      ticketUserID = userDetails[user].id

                  # Delete default assignment to bot user
                  options =
                    uri: "https://" + glpi_host + "/apirest.php/Ticket_User/" + ticketUserID
                    port: 443
                    method: 'DELETE'
                    headers: headersObj
                    form: postData

                  request options, (err, res, body) ->
                    if err
                      console.log(err)

                    options =
                      host: glpi_host
                      port: 443
                      path: "/apirest.php/killSession/"
                      headers: headersObj

                    https.get options, (res) ->
                      msg.send "Ticket created - https://" + glpi_host + "/front/ticket.form.php?id=" + newTicket[0].id
