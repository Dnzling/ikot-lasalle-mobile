"""Generate editable diagrams.net admin page flowcharts from current UI flows."""

from pathlib import Path
from xml.etree import ElementTree as ET


# Nodes: id, shape, label, column, row. Edges: source, target, optional label.
# Every decision has exactly one Yes exit and one No exit.
CHARTS = [
    ("01 Startup", "admin_app.dart: choose the first screen", [
        ("s", "terminal", "Start", 0, 0),
        ("init", "process", "Initialize Firebase and listen for auth state", 0, 1),
        ("signed", "decision", "Admin signed in?", 0, 2),
        ("login", "output", "Display Login page", 1, 2),
        ("shell", "output", "Display Admin Shell", 0, 3),
        ("e", "terminal", "End", 0, 4),
    ], [
        ("s", "init"), ("init", "signed"),
        ("signed", "login", "No"), ("signed", "shell", "Yes"),
        ("login", "e"), ("shell", "e"),
    ]),
    ("02 Login", "auth_screen.dart: ID and password sign in", [
        ("s", "terminal", "Start", 0, 0),
        ("show", "output", "Display ID and password fields", 0, 1),
        ("enter", "process", "Enter credentials and tap Sign in", 0, 2),
        ("valid", "decision", "Both fields entered?", 0, 3),
        ("missing", "output", "Show required credentials message", 1, 3),
        ("auth", "process", "Look up admin ID and authenticate", 0, 4),
        ("ok", "decision", "Authentication succeeded?", 0, 5),
        ("fail", "output", "Show Firebase or credential error", 1, 5),
        ("shell", "output", "Open Admin Shell", 0, 6),
        ("e", "terminal", "End", 0, 7),
    ], [
        ("s", "show"), ("show", "enter"), ("enter", "valid"),
        ("valid", "missing", "No"), ("missing", "enter"),
        ("valid", "auth", "Yes"), ("auth", "ok"),
        ("ok", "fail", "No"), ("fail", "enter"),
        ("ok", "shell", "Yes"), ("shell", "e"),
    ]),
    ("03 Admin Shell", "shell_screen.dart: sidebar and session controls", [
        ("s", "terminal", "Start", 0, 0),
        ("load", "process", "Load vehicle status timeout", 0, 1),
        ("show", "output", "Display sidebar, active page, alerts, admin badge", 0, 2),
        ("logout", "decision", "Log out selected?", 0, 3),
        ("prompt", "output", "Display logout confirmation", 1, 3),
        ("confirm", "decision", "Confirm log out?", 1, 4),
        ("signout", "process", "Sign out of Firebase", 2, 4),
        ("login", "output", "Open Login page", 2, 5),
        ("select", "process", "Choose one of the nine sidebar pages", 0, 4),
        ("page", "output", "Display selected admin page", 0, 5),
        ("e", "terminal", "End", 0, 6),
    ], [
        ("s", "load"), ("load", "show"), ("show", "logout"),
        ("logout", "prompt", "Yes"), ("prompt", "confirm"),
        ("confirm", "signout", "Yes"), ("confirm", "show", "No"),
        ("signout", "login"), ("login", "e"),
        ("logout", "select", "No"), ("select", "page"), ("page", "e"),
    ]),
    ("04 Dashboard", "dashboard_page.dart: live fleet and revenue overview", [
        ("s", "terminal", "Start", 0, 0),
        ("load", "process", "Read live vehicles, users, trips, and top-ups", 0, 1),
        ("show", "output", "Display earnings, active users, fleet counts, and status", 0, 2),
        ("period", "decision", "Month chart selected?", 0, 3),
        ("month", "output", "Display monthly revenue chart", 1, 3),
        ("week", "output", "Display weekly revenue chart", 0, 4),
        ("e", "terminal", "End", 0, 5),
    ], [
        ("s", "load"), ("load", "show"), ("show", "period"),
        ("period", "month", "Yes"), ("period", "week", "No"),
        ("month", "e"), ("week", "e"),
    ]),
    ("05 Vehicles", "vehicles_page.dart: fleet records, GPS, QR, archive", [
        ("s", "terminal", "Start", 0, 0),
        ("load", "process", "Read vehicles and live GPS data", 0, 1),
        ("show", "output", "Display fleet list, map, status, and revenue", 0, 2),
        ("register", "decision", "Register vehicle?", 0, 3),
        ("create", "process", "Validate type and plate; create vehicle", 1, 3),
        ("edit", "decision", "Edit vehicle?", 0, 4),
        ("save", "process", "Save vehicle details and assignment", 1, 4),
        ("gps", "decision", "Link GPS tracker?", 0, 5),
        ("link", "process", "Save tracker UID for vehicle", 1, 5),
        ("qr", "decision", "View boarding QR?", 0, 6),
        ("qrout", "output", "Display vehicle boarding QR", 1, 6),
        ("archive", "decision", "Archive, restore, or delete?", 0, 7),
        ("archive_done", "process", "Confirm and update vehicle record", 1, 7),
        ("e", "terminal", "End", 0, 8),
    ], [
        ("s", "load"), ("load", "show"), ("show", "register"),
        ("register", "create", "Yes"), ("create", "e"),
        ("register", "edit", "No"), ("edit", "save", "Yes"), ("save", "e"),
        ("edit", "gps", "No"), ("gps", "link", "Yes"), ("link", "e"),
        ("gps", "qr", "No"), ("qr", "qrout", "Yes"), ("qrout", "e"),
        ("qr", "archive", "No"), ("archive", "archive_done", "Yes"),
        ("archive_done", "e"), ("archive", "e", "No"),
    ]),
    ("06 Drivers", "drivers_page.dart: photo, assignment, pay, bulk inactivation, archive", [
        ("s", "terminal", "Start", 0, 0),
        ("load", "process", "Read active drivers and vehicle assignments", 0, 1),
        ("show", "output", "Display driver list, photos, salaries, and quotas", 0, 2),
        ("register", "decision", "Register driver?", 0, 3),
        ("create", "process", "Save driver, optional photo, and vehicle", 1, 3),
        ("edit", "decision", "Edit driver?", 0, 4),
        ("save", "process", "Update details, photo, active state, assignment", 1, 4),
        ("pay", "decision", "Compute salary?", 0, 5),
        ("receipt", "output", "Display salary calculation and receipt", 1, 5),
        ("archive", "decision", "Archive driver?", 0, 6),
        ("archive_done", "process", "Confirm and archive driver", 1, 6),
        ("bulk", "decision", "Inactivate selected drivers?", 0, 7),
        ("choose", "process", "Select active drivers and Resigned or Terminated", 1, 7),
        ("confirm_bulk", "decision", "Confirm bulk inactivation?", 1, 8),
        ("apply", "process", "Set inactive status and reason; unassign vehicles; audit", 2, 8),
        ("result", "output", "Display updated driver statuses", 2, 9),
        ("e", "terminal", "End", 0, 10),
    ], [
        ("s", "load"), ("load", "show"), ("show", "register"),
        ("register", "create", "Yes"), ("create", "e"),
        ("register", "edit", "No"), ("edit", "save", "Yes"), ("save", "e"),
        ("edit", "pay", "No"), ("pay", "receipt", "Yes"), ("receipt", "e"),
        ("pay", "archive", "No"), ("archive", "archive_done", "Yes"),
        ("archive_done", "e"), ("archive", "bulk", "No"),
        ("bulk", "choose", "Yes"), ("bulk", "e", "No"),
        ("choose", "confirm_bulk"), ("confirm_bulk", "apply", "Yes"),
        ("confirm_bulk", "e", "No"), ("apply", "result"), ("result", "e"),
    ]),
    ("07 Users", "users_page.dart: passenger accounts, import, PDF export, bulk inactivation", [
        ("s", "terminal", "Start", 0, 0),
        ("load", "process", "Read passenger accounts", 0, 1),
        ("show", "output", "Display user list and account details", 0, 2),
        ("create", "decision", "Create passenger?", 0, 3),
        ("create_done", "process", "Validate unique ID and create account", 1, 3),
        ("edit", "decision", "Edit passenger?", 0, 4),
        ("edit_done", "process", "Update profile and account fields", 1, 4),
        ("import", "decision", "Import users?", 0, 5),
        ("import_done", "process", "Read spreadsheet and create accounts", 1, 5),
        ("export", "decision", "Export PDF?", 0, 6),
        ("pdf", "output", "Generate and open users PDF", 1, 6),
        ("bulk", "decision", "Inactivate selected users?", 0, 7),
        ("choose", "process", "Select active students or staff/teachers; choose reason", 1, 7),
        ("valid", "decision", "Selection matches reason?", 1, 8),
        ("invalid", "output", "Show selection guidance", 2, 8),
        ("confirm_bulk", "decision", "Confirm bulk inactivation?", 1, 9),
        ("apply", "process", "Set inactive status and reason; revoke session; audit", 2, 9),
        ("result", "output", "Display updated user statuses", 2, 10),
        ("e", "terminal", "End", 0, 11),
    ], [
        ("s", "load"), ("load", "show"), ("show", "create"),
        ("create", "create_done", "Yes"), ("create_done", "e"),
        ("create", "edit", "No"), ("edit", "edit_done", "Yes"), ("edit_done", "e"),
        ("edit", "import", "No"), ("import", "import_done", "Yes"),
        ("import_done", "e"), ("import", "export", "No"),
        ("export", "pdf", "Yes"), ("pdf", "e"), ("export", "bulk", "No"),
        ("bulk", "choose", "Yes"), ("bulk", "e", "No"),
        ("choose", "valid"), ("valid", "invalid", "No"), ("invalid", "e"),
        ("valid", "confirm_bulk", "Yes"),
        ("confirm_bulk", "apply", "Yes"), ("confirm_bulk", "e", "No"),
        ("apply", "result"), ("result", "e"),
    ]),
    ("08 Top-ups", "top_up_page.dart: GCash and approval review", [
        ("s", "terminal", "Start", 0, 0),
        ("load", "process", "Read GCash settings and top-up requests", 0, 1),
        ("show", "output", "Display pending, approved, rejected requests", 0, 2),
        ("gcash", "decision", "Configure GCash?", 0, 3),
        ("gcash_done", "process", "Save account name and GCash number", 1, 3),
        ("review", "decision", "Review a request?", 0, 4),
        ("receipt", "output", "Display receipt and request details", 1, 4),
        ("approve", "decision", "Approve top-up?", 1, 5),
        ("credit", "process", "Credit passenger and record approval", 2, 5),
        ("reject", "process", "Enter reason and record rejection", 1, 6),
        ("e", "terminal", "End", 0, 7),
    ], [
        ("s", "load"), ("load", "show"), ("show", "gcash"),
        ("gcash", "gcash_done", "Yes"), ("gcash_done", "e"),
        ("gcash", "review", "No"), ("review", "receipt", "Yes"),
        ("review", "e", "No"), ("receipt", "approve"),
        ("approve", "credit", "Yes"), ("approve", "reject", "No"),
        ("credit", "e"), ("reject", "e"),
    ]),
    ("09 Routes", "routes_page.dart: points, radius, order, fare, archive", [
        ("s", "terminal", "Start", 0, 0),
        ("load", "process", "Read route points and map positions", 0, 1),
        ("show", "output", "Display ordered routes and map pins", 0, 2),
        ("add", "decision", "Add route?", 0, 3),
        ("create", "process", "Set name, pin or coordinates, radius; save", 1, 3),
        ("edit", "decision", "Edit route?", 0, 4),
        ("save", "process", "Update route, position, radius, or fare", 1, 4),
        ("reorder", "decision", "Reorder routes?", 0, 5),
        ("order", "process", "Save new route order", 1, 5),
        ("state", "decision", "Change active or archived state?", 0, 6),
        ("state_done", "process", "Activate, deactivate, archive, or restore", 1, 6),
        ("e", "terminal", "End", 0, 7),
    ], [
        ("s", "load"), ("load", "show"), ("show", "add"),
        ("add", "create", "Yes"), ("create", "e"),
        ("add", "edit", "No"), ("edit", "save", "Yes"), ("save", "e"),
        ("edit", "reorder", "No"), ("reorder", "order", "Yes"), ("order", "e"),
        ("reorder", "state", "No"), ("state", "state_done", "Yes"),
        ("state_done", "e"), ("state", "e", "No"),
    ]),
    ("10 Fare Settings", "fare_page.dart: global default and round-trip fares", [
        ("s", "terminal", "Start", 0, 0),
        ("load", "process", "Read current fare settings", 0, 1),
        ("show", "output", "Display default and round-trip fare", 0, 2),
        ("edit", "decision", "Edit fares?", 0, 3),
        ("entry", "process", "Enter new fare amounts", 1, 3),
        ("valid", "decision", "Amounts valid?", 1, 4),
        ("bad", "output", "Show validation error", 2, 4),
        ("save", "process", "Save fares and audit activity", 1, 5),
        ("result", "output", "Display updated fares", 1, 6),
        ("e", "terminal", "End", 0, 7),
    ], [
        ("s", "load"), ("load", "show"), ("show", "edit"),
        ("edit", "entry", "Yes"), ("edit", "e", "No"),
        ("entry", "valid"), ("valid", "bad", "No"), ("bad", "entry"),
        ("valid", "save", "Yes"), ("save", "result"), ("result", "e"),
    ]),
    ("11 Reports and Exports", "reports_page.dart: live records, filters, PDF", [
        ("s", "terminal", "Start", 0, 0),
        ("load", "process", "Read transactions, vehicle performance, trips", 0, 1),
        ("show", "output", "Display report tables and summary values", 0, 2),
        ("filter", "process", "Choose status, date range, or report section", 0, 3),
        ("rows", "decision", "Matching rows available?", 0, 4),
        ("empty", "output", "Show empty report state", 1, 4),
        ("pdf", "decision", "Export PDF selected?", 0, 5),
        ("create", "process", "Generate PDF and record export log", 1, 5),
        ("result", "output", "Open or save PDF", 1, 6),
        ("e", "terminal", "End", 0, 7),
    ], [
        ("s", "load"), ("load", "show"), ("show", "filter"),
        ("filter", "rows"), ("rows", "empty", "No"), ("empty", "e"),
        ("rows", "pdf", "Yes"), ("pdf", "create", "Yes"),
        ("pdf", "e", "No"), ("create", "result"), ("result", "e"),
    ]),
    ("12 Settings", "settings_page.dart: timing, fueling pins, audit logs", [
        ("s", "terminal", "Start", 0, 0),
        ("load", "process", "Read vehicle timeout and fueling locations", 0, 1),
        ("show", "output", "Display timing, entrance and exit, audit link", 0, 2),
        ("timing", "decision", "Edit offline timing?", 0, 3),
        ("timing_save", "process", "Validate 10 to 3600 seconds; save", 1, 3),
        ("fuel", "decision", "Edit fueling locations?", 0, 4),
        ("pins", "process", "Set entrance and exit pins or coordinates and radii", 1, 4),
        ("preview", "output", "Preview both gates on map", 1, 5),
        ("confirm", "decision", "Confirm save?", 1, 6),
        ("fuel_save", "process", "Save fueling gate settings", 2, 6),
        ("audit", "decision", "Open Audit Logs?", 0, 5),
        ("audit_page", "output", "Open Audit Logs page", 0, 6),
        ("e", "terminal", "End", 0, 7),
    ], [
        ("s", "load"), ("load", "show"), ("show", "timing"),
        ("timing", "timing_save", "Yes"), ("timing_save", "e"),
        ("timing", "fuel", "No"), ("fuel", "pins", "Yes"),
        ("pins", "preview"), ("preview", "confirm"),
        ("confirm", "fuel_save", "Yes"), ("confirm", "e", "No"),
        ("fuel_save", "e"), ("fuel", "audit", "No"),
        ("audit", "audit_page", "Yes"), ("audit_page", "e"),
        ("audit", "e", "No"),
    ]),
    ("13 Audit Logs", "audit_logs_page.dart: admin changes and exports", [
        ("s", "terminal", "Start", 0, 0),
        ("load", "process", "Read admin activity and export logs", 0, 1),
        ("error", "decision", "Loading failed?", 0, 2),
        ("fail", "output", "Show load error", 1, 2),
        ("empty", "decision", "Logs empty?", 0, 3),
        ("none", "output", "Show no activity message", 1, 3),
        ("list", "output", "Display newest logs first", 0, 4),
        ("open", "decision", "Open log detail?", 0, 5),
        ("detail", "output", "Show action, details, admin, time", 1, 5),
        ("e", "terminal", "End", 0, 6),
    ], [
        ("s", "load"), ("load", "error"), ("error", "fail", "Yes"),
        ("fail", "e"), ("error", "empty", "No"),
        ("empty", "none", "Yes"), ("none", "e"),
        ("empty", "list", "No"), ("list", "open"),
        ("open", "detail", "Yes"), ("detail", "e"),
        ("open", "e", "No"),
    ]),
    ("14 Notifications", "admin_notifications.dart: badge and alert dialog", [
        ("s", "terminal", "Start", 0, 0),
        ("load", "process", "Load alerts and saved read state", 0, 1),
        ("badge", "output", "Display unread badge in shell", 0, 2),
        ("open", "decision", "Open notifications?", 0, 3),
        ("dialog", "output", "Display alert list and mark alerts read", 1, 3),
        ("select", "decision", "Open an alert?", 1, 4),
        ("preview", "output", "Display alert detail", 2, 4),
        ("navigate", "decision", "Go to related page?", 2, 5),
        ("page", "output", "Display related admin page", 2, 6),
        ("e", "terminal", "End", 0, 7),
    ], [
        ("s", "load"), ("load", "badge"), ("badge", "open"),
        ("open", "dialog", "Yes"), ("open", "e", "No"),
        ("dialog", "select"), ("select", "preview", "Yes"),
        ("select", "e", "No"), ("preview", "navigate"),
        ("navigate", "page", "Yes"), ("navigate", "e", "No"),
        ("page", "e"),
    ]),
]

STYLES = {
    "terminal": "rounded=1;arcSize=50;whiteSpace=wrap;html=1;fillColor=#DDF2E4;strokeColor=#08783E;fontColor=#064A2B;strokeWidth=2;",
    "process": "rounded=0;whiteSpace=wrap;html=1;fillColor=#FFFFFF;strokeColor=#315E49;fontColor=#18382A;strokeWidth=2;",
    "output": "shape=parallelogram;perimeter=parallelogramPerimeter;whiteSpace=wrap;html=1;fillColor=#E4F3FF;strokeColor=#367BAA;fontColor=#173C57;strokeWidth=2;",
    "decision": "rhombus;whiteSpace=wrap;html=1;fillColor=#FFF0CC;strokeColor=#B77913;fontColor=#553609;strokeWidth=2;",
}


def chart_model(title, note, nodes, edges):
    node_ids = {node_id for node_id, *_ in nodes}
    assert len(node_ids) == len(nodes)
    assert sum(kind == "terminal" and label == "Start" for _, kind, label, *_ in nodes) == 1
    assert sum(kind == "terminal" and label == "End" for _, kind, label, *_ in nodes) == 1
    exits = {}
    for source, target, *label in edges:
        assert source in node_ids and target in node_ids
        exits.setdefault(source, []).append(label[0] if label else "")
    for node_id, kind, *_ in nodes:
        if kind == "decision":
            assert sorted(exits[node_id]) == ["No", "Yes"], (title, node_id)

    model = ET.Element("mxGraphModel", {
        "dx": "1600", "dy": "900", "grid": "1", "gridSize": "10", "guides": "1",
        "tooltips": "1", "connect": "1", "arrows": "1", "fold": "1", "page": "1",
        "pageScale": "1", "pageWidth": "1550",
        "pageHeight": str(max(1169, 270 + 125 * max(row for *_, row in nodes))),
        "math": "0", "shadow": "0",
    })
    root = ET.SubElement(model, "root")
    ET.SubElement(root, "mxCell", {"id": "0"})
    ET.SubElement(root, "mxCell", {"id": "1", "parent": "0"})
    header = ET.SubElement(root, "mxCell", {
        "id": "header", "value": f"{title} | {note}",
        "style": "text;html=1;align=left;verticalAlign=middle;whiteSpace=wrap;fontSize=16;fontStyle=1;fontColor=#064A2B;",
        "vertex": "1", "parent": "1",
    })
    ET.SubElement(header, "mxGeometry", {"x": "65", "y": "25", "width": "1400", "height": "40", "as": "geometry"})
    for node_id, kind, label, col, row in nodes:
        cell = ET.SubElement(root, "mxCell", {
            "id": node_id, "value": label,
            "style": STYLES[kind] + "fontSize=13;align=center;verticalAlign=middle;spacing=8;",
            "vertex": "1", "parent": "1",
        })
        ET.SubElement(cell, "mxGeometry", {
            "x": str(65 + col * 410), "y": str(95 + row * 125),
            "width": "310" if kind == "decision" else "300",
            "height": "100" if kind == "decision" else "68", "as": "geometry",
        })
    for index, (source, target, *label) in enumerate(edges):
        cell = ET.SubElement(root, "mxCell", {
            "id": f"edge{index}", "value": label[0] if label else "",
            "style": "edgeStyle=orthogonalEdgeStyle;rounded=1;orthogonalLoop=1;jettySize=auto;html=1;endArrow=block;endFill=1;strokeColor=#5B7064;fontSize=12;fontStyle=1;labelBackgroundColor=#FFFFFF;",
            "edge": "1", "parent": "1", "source": source, "target": target,
        })
        ET.SubElement(cell, "mxGeometry", {"relative": "1", "as": "geometry"})
    return model


def main():
    document = ET.Element("mxfile", {
        "host": "app.diagrams.net", "agent": "Codex", "pages": str(len(CHARTS)),
    })
    for index, (title, note, nodes, edges) in enumerate(CHARTS, 1):
        diagram = ET.SubElement(document, "diagram", {"id": f"admin-page-{index}", "name": title})
        diagram.append(chart_model(title, note, nodes, edges))
    output = Path(__file__).with_name("admin_page_flowcharts.drawio")
    ET.indent(document, space="  ")
    ET.ElementTree(document).write(output, encoding="utf-8", xml_declaration=False)
    print(f"Created {output} with {len(CHARTS)} page flowcharts")


if __name__ == "__main__":
    main()
