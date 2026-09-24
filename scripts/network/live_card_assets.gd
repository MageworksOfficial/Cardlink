extends Node
## Refresh presentation only; never replay a public snapshot over moving cards.
var service: Node
var queue: Array[String] = []
var refresh_views: bool = false
func _ready() -> void: service.asset_available.connect(schedule)
func resolve_public(state: RefCounted, data: Dictionary) -> void:
    if bool(data.face_down) or str(data.definition).is_empty() or service.catalog == null: return
    for row: Dictionary in service.own + service.remote:
        if row.id != data.definition or not data.art in service.Catalog.images(row): continue
        var faces: Array = row.get("faces",[{"name":row.name,"hash":row.hash}])
        var local_faces: Array = []
        for i: int in faces.size():
            local_faces.append({"face_id":"face_"+str(i),"face_index":i,"name":faces[i].name,"image_hash":faces[i].hash,"image_path":service.catalog.asset_path(faces[i].hash) if service.catalog.has_image(faces[i].hash) else ""})
        state.faces = local_faces
        if state.active_face_index >= 0 and state.active_face_index < local_faces.size():
            state.image_path = local_faces[state.active_face_index].image_path
        return
func schedule(hash_value: String) -> void:
    if service.router.table == null: return
    var c: Node = service.router.table.match_controller
    for row: Dictionary in service.router.state.get("hands",{}).get(service.router.remote_id,[]):
        if row.art == hash_value: refresh_views = true
    for row: Dictionary in c.remote_library_knowledge.values():
        if row.art == hash_value: refresh_views = true
    if c.remote_inspection and service.router.hidden.outgoing != null:
        for row: Dictionary in service.router.hidden.outgoing.rows:
            if row.art == hash_value: refresh_views = true
    # Include locally held known instances (e.g. a card transferred into hand).
    for card: Control in service.router.table.cards:
        if card.state.face_down: continue
        for row: Dictionary in service.own + service.remote:
            if row.id == card.state.card_definition_id and hash_value in service.Catalog.images(row):
                if not card.state.match_instance_id in queue: queue.append(card.state.match_instance_id)
    for data: Dictionary in service.router.state.cards.values():
        if data.face_down or str(data.definition).is_empty(): continue
        var relevant: bool = data.art == hash_value
        for row: Dictionary in service.remote:
            if row.id == data.definition and hash_value in service.Catalog.images(row): relevant = true
        if relevant and not data.id in queue: queue.append(data.id)
func _process(_delta: float) -> void:
    if service.router.table == null: return
    if refresh_views:
        refresh_views = false
        service.router.table.match_controller.refresh()
        return
    if queue.is_empty(): return
    # At most one visible instance texture per frame; all duplicates eventually refresh.
    var id: String = queue.pop_front()
    var data: Dictionary = service.router.state.cards.get(id,{})
    var table: Node = service.router.table
    var card: Control = table.match_controller.card_by_id(id)
    if card == null or card.state.face_down: return
    if data.is_empty():
        for row: Dictionary in service.own + service.remote:
            if row.id != card.state.card_definition_id: continue
            var faces: Array = row.get("faces",[{"hash":row.hash}])
            var index: int = card.state.active_face_index
            if index >= 0 and index < faces.size(): data = {"definition":row.id,"art":faces[index].hash,"face_down":false}
            break
    if data.is_empty() or data.face_down: return
    resolve_public(card.state,data)
    table.apply_card_art(card)
    card.tooltip_text = "" if card.card_image.texture != null else "Card image missing — Sync Missing Cards."
    if card.state.current_zone in ["hand","library"]: refresh_views = true
