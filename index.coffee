# Labs ~ obj importer

# Dependencies.
fs          = require('fs')
util        = require('util')
http        = require('http')
async       = require('async')
formidable  = require('formidable')
querystring   = require('querystring')

#
client = http.createClient(80, 'api.stash3.com')

# 
# Request a POST resource and get back the result as object.
# @param url{String}
# @param fn{Function}
# @param vars{Object}
#
post = (url, fn, vars = {}) ->
   data = querystring.stringify vars, '&', '='
   req = client.request 'POST', url, {
      'Host':'api.stash3.com',
      'Content-Type':'application/x-www-form-urlencoded',
      'Content-Length':data.length
   }
   req.on 'response', (res) ->
      res.setEncoding 'utf8'
      result = ''
      res.on 'data', (chunk) -> result += chunk
      res.on 'end', () -> fn JSON.parse result
   req.end(data)

#
# Helper function to parse OBJ string.
# @param data {String} containing the content of the OBJ file.
# @return vertices {Array} and faces {Array}.
#
parseOBJString = (data) ->
   vertices = []
   faces = []
   lines = data.split('\n')
   for line in lines
      # Replace exotic white space with ' ' and split in an array.
      lineParts = line.replace(/\s+/, ' ').split(' ')
      if lineParts[0] is 'v'
         # Vertex
         vertices.push [
            parseFloat lineParts[1]
            parseFloat lineParts[2]
            parseFloat lineParts[3]
         ]
      else if lineParts[0] is 'f'
         # Face (first vertex is at index 1).
        faces.push [
           parseFloat lineParts[1].split('/')[0]-1
           parseFloat lineParts[2].split('/')[0]-1
           parseFloat lineParts[3].split('/')[0]-1
        ]
   # Return multiple values
   [vertices, faces]

#
# Use the api to input the triangle faces and then group them together.
# @param vertices {Array}
# @param faces {Array}
# @param stashId {String}
# @param userId {String}
# @param fn {Function} 
# @return triangleIds {Array}
#
injectTrianglesAndGroup = (vertices, faces, stashId, userId, fn) ->
   triangleIds = []
   tasks = []
   i = 0
   for x in [0..faces.length-1]
      # Insert new triangle in stash.
      tasks.push( (cb) ->
         post(
            "/v1/stashes/#{stashId}/create/triangle"
            (r) ->
               triangleIds.push( r.id )
               console.log "triangleId:#{r.id}"
               cb()
            {
               user_id:userId
               v0_x:vertices[faces[i][0]][0]*10.0
               v0_y:vertices[faces[i][0]][1]*10.0
               v0_z:vertices[faces[i][0]][2]*10.0
               v1_x:vertices[faces[i][1]][0]*10.0
               v1_y:vertices[faces[i][1]][1]*10.0
               v1_z:vertices[faces[i][1]][2]*10.0
               v2_x:vertices[faces[i][2]][0]*10.0
               v2_y:vertices[faces[i][2]][1]*10.0
               v2_z:vertices[faces[i++][2]][2]*10.0
            }
         )
      )
   async.parallel tasks, (err, r) ->
      if err
         return fn err
      # Group them together.
      post(
         "/v1/stashes/#{stashId}/create/group"
         (r) -> 
            console.log "Grouping done -> #{stashId}"
            fn null
         {
            object_ids: triangleIds.join(",")
            user_id: userId
         }
      )

#
# Setup routing.
#
module.exports.setup = (server, url) ->
   # GET /
   server.get(url, (req, res, next) ->
      console.log(url+' '+req.method+' '+req.url)
      res.render(__dirname + '/views/index', {
         title:'OBJ File Importer | Stash3',
         url:url
      })
   )
   # POST /
   server.post url, (req, res, next) ->
      console.log url+' '+req.method+' '+req.url
      form = new formidable.IncomingForm()
      form.parse req, (err, fields, files) ->
         if err
            return next error err
         #console.log "fields:#{JSON.stringify fields} files: #{JSON.stringify files}"
         if not fields.user_id or not fields.stash_id
            return next error 'Missing parameters.'
         if not files.file or not files.file.path
            return next error 'Missing file.'

         userId = fields.user_id
         stashId = fields.stash_id
         filePath = files.file.path

         fs.readFile files.file.path, 'utf8', (err, data) ->
            if err
               return next error err

            [vertices, faces] = parseOBJString data
            injectTrianglesAndGroup vertices, faces, stashId, userId, (err) ->
                  if err
                     return next error err
                  res.writeHead 200, {'content-type': 'text/plain'}
                  res.end 'upload ok!'
