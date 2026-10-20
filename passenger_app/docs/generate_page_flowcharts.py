"""Generate editable, page-by-page diagrams.net flowcharts for the passenger app."""

from pathlib import Path
from xml.etree import ElementTree as ET


# Each chart has one Start and one End. Decisions have Yes and No exits only.
# Node: id, kind, text, column, row. Edge: from, to, optional label.
CHARTS = [
    ("01 Startup", "app.dart: restore session and choose the first screen", [
        ("s", "terminal", "Start", 0, 0), ("restore", "process", "Restore saved session", 0, 1),
        ("error", "decision", "Restore failed?", 0, 2), ("retry", "output", "Show connection error and Retry", 1, 2),
        ("session", "decision", "Session found?", 0, 3), ("login", "output", "Display Login page", 1, 3),
        ("password", "decision", "Must change password?", 0, 4),
        ("change", "output", "Display forced Change Password page", 1, 4),
        ("shell", "output", "Display Passenger Shell", 0, 5), ("e", "terminal", "End", 0, 6),
    ], [
        ("s", "restore"), ("restore", "error"), ("error", "retry", "Yes"), ("retry", "restore"),
        ("error", "session", "No"), ("session", "login", "No"), ("session", "password", "Yes"),
        ("password", "change", "Yes"), ("password", "shell", "No"),
        ("login", "e"), ("change", "e"), ("shell", "e"),
    ]),
    ("02 Login", "login_screen.dart: sign in, reset access, and first password change", [
        ("s", "terminal", "Start", 0, 0), ("show", "output", "Display ID and password fields", 0, 1),
        ("forgot", "decision", "Forgot password tapped?", 0, 2),
        ("reset", "output", "Open Forgot Password page", 1, 2),
        ("input", "process", "Enter ID and password; tap Sign in", 0, 3),
        ("valid", "decision", "Fields valid?", 0, 4),
        ("validation", "output", "Show required field errors", 1, 4),
        ("auth", "process", "Authenticate and load passenger session", 0, 5),
        ("success", "decision", "Sign in succeeded?", 0, 6),
        ("failure", "output", "Show sign in or new device message", 1, 6),
        ("must", "decision", "Default password still active?", 0, 7),
        ("change", "output", "Open forced Change Password page", 1, 7),
        ("shell", "output", "Open Passenger Shell", 0, 8), ("e", "terminal", "End", 0, 9),
    ], [
        ("s", "show"), ("show", "forgot"), ("forgot", "reset", "Yes"), ("reset", "e"),
        ("forgot", "input", "No"), ("input", "valid"), ("valid", "validation", "No"),
        ("validation", "input"), ("valid", "auth", "Yes"), ("auth", "success"),
        ("success", "failure", "No"), ("failure", "input"), ("success", "must", "Yes"),
        ("must", "change", "Yes"), ("must", "shell", "No"), ("change", "e"), ("shell", "e"),
    ]),
    ("03 Registration", "registration_screen.dart: implemented page; currently no link from Login", [
        ("s", "terminal", "Start", 0, 0), ("show", "output", "Display registration form", 0, 1),
        ("entry", "process", "Enter names, ID, phone, and password", 0, 2),
        ("valid", "decision", "Form valid?", 0, 3), ("invalid", "output", "Show validation errors", 1, 3),
        ("create", "process", "Create passenger account", 0, 4),
        ("success", "decision", "Creation succeeded?", 0, 5),
        ("fail", "output", "Show registration error", 1, 5),
        ("shell", "output", "Open Passenger Shell", 0, 6), ("e", "terminal", "End", 0, 7),
    ], [
        ("s", "show"), ("show", "entry"), ("entry", "valid"), ("valid", "invalid", "No"),
        ("invalid", "entry"), ("valid", "create", "Yes"), ("create", "success"),
        ("success", "fail", "No"), ("fail", "entry"), ("success", "shell", "Yes"), ("shell", "e"),
    ]),
    ("04 Forgot Password", "forgot_password_screen.dart: email-only reset link", [
        ("s", "terminal", "Start", 0, 0), ("show", "output", "Display reset form", 0, 1),
        ("entry", "process", "Enter account email address", 0, 2),
        ("valid", "decision", "Form valid?", 0, 3), ("invalid", "output", "Show field errors", 1, 3),
        ("send", "process", "Request password reset link", 0, 4),
        ("success", "decision", "Request succeeded?", 0, 5),
        ("fail", "output", "Show send error", 1, 5),
        ("notice", "output", "Show Check your email message", 0, 6),
        ("back", "process", "Return to Login", 0, 7), ("e", "terminal", "End", 0, 8),
    ], [
        ("s", "show"), ("show", "entry"), ("entry", "valid"), ("valid", "invalid", "No"),
        ("invalid", "entry"), ("valid", "send", "Yes"), ("send", "success"),
        ("success", "fail", "No"), ("fail", "entry"), ("success", "notice", "Yes"),
        ("notice", "back"), ("back", "e"),
    ]),
    ("05 Forced Password Change", "change_password_screen.dart: required after default password login", [
        ("s", "terminal", "Start", 0, 0), ("show", "output", "Display new password form", 0, 1),
        ("entry", "process", "Enter and confirm new password", 0, 2),
        ("valid", "decision", "Password valid and matching?", 0, 3),
        ("invalid", "output", "Show password errors", 1, 3),
        ("save", "process", "Save password and clear required change", 0, 4),
        ("success", "decision", "Save succeeded?", 0, 5),
        ("fail", "output", "Show save error", 1, 5),
        ("shell", "output", "Open Passenger Shell", 0, 6), ("e", "terminal", "End", 0, 7),
    ], [
        ("s", "show"), ("show", "entry"), ("entry", "valid"), ("valid", "invalid", "No"),
        ("invalid", "entry"), ("valid", "save", "Yes"), ("save", "success"),
        ("success", "fail", "No"), ("fail", "entry"), ("success", "shell", "Yes"), ("shell", "e"),
    ]),
    ("06 Passenger Shell", "passenger_shell.dart: bottom navigation", [
        ("s", "terminal", "Start", 0, 0), ("tabs", "output", "Display Home, Transactions, Alerts, Profile tabs", 0, 1),
        ("select", "process", "Select a tab", 0, 2),
        ("home", "decision", "Home selected?", 0, 3), ("home_out", "output", "Display Home page", 1, 3),
        ("credits", "decision", "Transactions selected?", 0, 4),
        ("credits_out", "output", "Display Transactions page", 1, 4),
        ("alerts", "decision", "Alerts selected?", 0, 5),
        ("alerts_out", "output", "Display Alerts page", 1, 5),
        ("profile", "output", "Display Profile page", 0, 6), ("e", "terminal", "End", 0, 7),
    ], [
        ("s", "tabs"), ("tabs", "select"), ("select", "home"),
        ("home", "home_out", "Yes"), ("home", "credits", "No"),
        ("credits", "credits_out", "Yes"), ("credits", "alerts", "No"),
        ("alerts", "alerts_out", "Yes"), ("alerts", "profile", "No"),
        ("home_out", "e"), ("credits_out", "e"), ("alerts_out", "e"), ("profile", "e"),
    ]),
    ("07 Home", "home_screen.dart: map, email verification, active trip", [
        ("s", "terminal", "Start", 0, 0), ("load", "process", "Load live buses and active trip", 0, 1),
        ("show", "output", "Display campus map and trip status", 0, 2),
        ("verified", "decision", "Email verified?", 0, 3),
        ("verify", "output", "Show add or verify email card", 1, 3),
        ("trip", "decision", "Active trip exists?", 0, 4),
        ("waiting", "output", "Open Your Ride page", 1, 4),
        ("booking", "output", "Open Book a Ride page", 0, 5), ("e", "terminal", "End", 0, 6),
    ], [
        ("s", "load"), ("load", "show"), ("show", "verified"),
        ("verified", "verify", "No"), ("verify", "trip"), ("verified", "trip", "Yes"),
        ("trip", "waiting", "Yes"), ("trip", "booking", "No"),
        ("waiting", "e"), ("booking", "e"),
    ]),
    ("08 Book a Ride", "booking_screen.dart: GPS pickup, destination, fare, booking", [
        ("s", "terminal", "Start", 0, 0), ("load", "process", "Load active routes and fares", 0, 1),
        ("enough", "decision", "At least two routes?", 0, 2),
        ("missing", "output", "Show routes unavailable message", 1, 2),
        ("gps", "process", "Detect GPS pickup inside stop radius", 0, 3),
        ("inside", "decision", "Pickup detected?", 0, 4),
        ("outside", "output", "Show GPS or radius retry message", 1, 4),
        ("select", "process", "Select destination and 1 to 6 passengers", 0, 5),
        ("fare", "output", "Show calculated fare", 0, 6),
        ("valid", "decision", "Trip selection valid?", 0, 7),
        ("invalid", "output", "Keep Start booking disabled", 1, 7),
        ("create", "process", "Refresh fare and create booking", 0, 8),
        ("success", "decision", "Booking saved?", 0, 9),
        ("fail", "output", "Show booking error", 1, 9),
        ("wait", "output", "Open Your Ride page", 0, 10), ("e", "terminal", "End", 0, 11),
    ], [
        ("s", "load"), ("load", "enough"), ("enough", "missing", "No"),
        ("missing", "e"), ("enough", "gps", "Yes"), ("gps", "inside"),
        ("inside", "outside", "No"), ("outside", "gps"), ("inside", "select", "Yes"),
        ("select", "fare"), ("fare", "valid"), ("valid", "invalid", "No"),
        ("invalid", "select"), ("valid", "create", "Yes"), ("create", "success"),
        ("success", "fail", "No"), ("fail", "select"), ("success", "wait", "Yes"), ("wait", "e"),
    ]),
    ("09 Your Ride", "waiting_screen.dart: wait, QR boarding, cancellation, arrival", [
        ("s", "terminal", "Start", 0, 0), ("show", "output", "Display fare, map, vehicle, and ride status", 0, 1),
        ("boarded", "decision", "Already onboard?", 0, 2),
        ("cancel", "decision", "Cancel or 10 minute expiry?", 1, 2),
        ("cancel_done", "process", "Cancel booking", 2, 2),
        ("scan", "process", "Open QR scanner and board", 1, 3),
        ("scan_ok", "decision", "Valid boarding QR?", 1, 4),
        ("bad", "output", "Show scan or boarding error", 2, 4),
        ("paid", "output", "Show paid fare and ETA", 0, 5),
        ("arrive", "decision", "Destination reached?", 0, 6),
        ("wait", "output", "Continue map and ETA updates", 1, 6),
        ("complete", "process", "Complete ride", 0, 7),
        ("done", "output", "Show Ride completed and return Home", 0, 8),
        ("canceled", "output", "Show canceled notice and return", 2, 3),
        ("e", "terminal", "End", 0, 9),
    ], [
        ("s", "show"), ("show", "boarded"), ("boarded", "cancel", "No"),
        ("cancel", "cancel_done", "Yes"), ("cancel_done", "canceled"), ("canceled", "e"),
        ("cancel", "scan", "No"), ("scan", "scan_ok"), ("scan_ok", "bad", "No"),
        ("bad", "scan"), ("scan_ok", "paid", "Yes"), ("boarded", "paid", "Yes"),
        ("paid", "arrive"), ("arrive", "wait", "No"), ("wait", "arrive"),
        ("arrive", "complete", "Yes"), ("complete", "done"), ("done", "e"),
    ]),
    ("10 QR Scanner", "waiting_screen.dart: private Boarding Scanner route", [
        ("s", "terminal", "Start", 0, 0), ("camera", "process", "Open camera scanner", 0, 1),
        ("found", "decision", "QR detected?", 0, 2),
        ("keep", "output", "Keep scanning", 1, 2),
        ("return", "process", "Return QR payload to Your Ride", 0, 3),
        ("e", "terminal", "End", 0, 4),
    ], [
        ("s", "camera"), ("camera", "found"), ("found", "keep", "No"),
        ("keep", "found"), ("found", "return", "Yes"), ("return", "e"),
    ]),
    ("11 Transactions", "credits_screen.dart: balance, requests, top up entry", [
        ("s", "terminal", "Start", 0, 0), ("load", "process", "Load credits and top-up requests", 0, 1),
        ("show", "output", "Display balance and request history", 0, 2),
        ("topup", "decision", "Request top up tapped?", 0, 3),
        ("page", "output", "Open Top Up page", 1, 3),
        ("refresh", "decision", "Pull to refresh?", 0, 4),
        ("back", "process", "Stay on or leave Transactions tab", 0, 5),
        ("e", "terminal", "End", 0, 6),
    ], [
        ("s", "load"), ("load", "show"), ("show", "topup"),
        ("topup", "page", "Yes"), ("page", "e"), ("topup", "refresh", "No"),
        ("refresh", "load", "Yes"), ("refresh", "back", "No"), ("back", "e"),
    ]),
    ("12 Top Up", "top_up_screen.dart: GCash details, receipt OCR, submit", [
        ("s", "terminal", "Start", 0, 0), ("load", "process", "Load GCash payment details", 0, 1),
        ("show", "output", "Display GCash number and top-up form", 0, 2),
        ("receipt", "process", "Attach receipt and scan text", 0, 3),
        ("entry", "process", "Enter amount and 13 digit reference", 0, 4),
        ("valid", "decision", "Receipt and entries valid?", 0, 5),
        ("invalid", "output", "Show amount, receipt, or reference error", 1, 5),
        ("submit", "process", "Submit top-up request", 0, 6),
        ("success", "decision", "Request saved?", 0, 7),
        ("fail", "output", "Show failure or timeout message", 1, 7),
        ("return", "output", "Return to refreshed Transactions page", 0, 8),
        ("e", "terminal", "End", 0, 9),
    ], [
        ("s", "load"), ("load", "show"), ("show", "receipt"), ("receipt", "entry"),
        ("entry", "valid"), ("valid", "invalid", "No"), ("invalid", "entry"),
        ("valid", "submit", "Yes"), ("submit", "success"), ("success", "fail", "No"),
        ("fail", "entry"), ("success", "return", "Yes"), ("return", "e"),
    ]),
    ("13 Alerts", "alerts_screen.dart: notification list and refresh", [
        ("s", "terminal", "Start", 0, 0), ("load", "process", "Load passenger notifications", 0, 1),
        ("error", "decision", "Loading failed?", 0, 2),
        ("retry", "output", "Show error and Retry", 1, 2),
        ("empty", "decision", "Notifications empty?", 0, 3),
        ("none", "output", "Show no notifications message", 1, 3),
        ("list", "output", "Display ride and credit alerts", 0, 4),
        ("refresh", "decision", "Pull to refresh?", 0, 5),
        ("e", "terminal", "End", 0, 6),
    ], [
        ("s", "load"), ("load", "error"), ("error", "retry", "Yes"),
        ("retry", "load"), ("error", "empty", "No"), ("empty", "none", "Yes"),
        ("none", "refresh"), ("empty", "list", "No"), ("list", "refresh"),
        ("refresh", "load", "Yes"), ("refresh", "e", "No"),
    ]),
    ("14 Profile", "profile_screen.dart: account details and account actions", [
        ("s", "terminal", "Start", 0, 0), ("show", "output", "Display name, ID, and email status", 0, 1),
        ("email", "decision", "Edit email tapped?", 0, 2),
        ("edit", "process", "Add or change email; send or check verification", 1, 2),
        ("email_out", "output", "Show updated email status", 1, 3),
        ("password", "decision", "Change password tapped?", 0, 3),
        ("password_page", "output", "Open Profile Change Password page", 0, 4),
        ("logout", "decision", "Log out tapped?", 1, 4),
        ("prompt", "output", "Display logout confirmation", 1, 5),
        ("confirm", "decision", "Confirm log out?", 1, 6),
        ("signout", "process", "Sign out and clear session", 2, 6),
        ("login", "output", "Open Login page", 2, 7), ("e", "terminal", "End", 0, 8),
    ], [
        ("s", "show"), ("show", "email"), ("email", "edit", "Yes"),
        ("edit", "email_out"), ("email_out", "password"), ("email", "password", "No"),
        ("password", "password_page", "Yes"), ("password_page", "e"),
        ("password", "logout", "No"), ("logout", "prompt", "Yes"),
        ("prompt", "confirm"), ("confirm", "signout", "Yes"),
        ("confirm", "show", "No"),
        ("signout", "login"), ("login", "e"), ("logout", "e", "No"),
    ]),
    ("15 Profile Change Password", "profile_change_password_screen.dart: change current password", [
        ("s", "terminal", "Start", 0, 0), ("show", "output", "Display current, new, confirm fields", 0, 1),
        ("entry", "process", "Enter current and new passwords", 0, 2),
        ("valid", "decision", "Form valid?", 0, 3),
        ("invalid", "output", "Show password validation errors", 1, 3),
        ("save", "process", "Update password", 0, 4),
        ("success", "decision", "Password updated?", 0, 5),
        ("fail", "output", "Show authentication or save error", 1, 5),
        ("return", "output", "Return to Profile with success notice", 0, 6),
        ("e", "terminal", "End", 0, 7),
    ], [
        ("s", "show"), ("show", "entry"), ("entry", "valid"),
        ("valid", "invalid", "No"), ("invalid", "entry"),
        ("valid", "save", "Yes"), ("save", "success"),
        ("success", "fail", "No"), ("fail", "entry"),
        ("success", "return", "Yes"), ("return", "e"),
    ]),
]

STYLE = {
    "terminal": "rounded=1;arcSize=50;whiteSpace=wrap;html=1;fillColor=#DDF2E4;strokeColor=#08783E;fontColor=#064A2B;strokeWidth=2;",
    "process": "rounded=0;whiteSpace=wrap;html=1;fillColor=#FFFFFF;strokeColor=#315E49;fontColor=#18382A;strokeWidth=2;",
    "output": "shape=parallelogram;perimeter=parallelogramPerimeter;whiteSpace=wrap;html=1;fillColor=#E4F3FF;strokeColor=#367BAA;fontColor=#173C57;strokeWidth=2;",
    "decision": "rhombus;whiteSpace=wrap;html=1;fillColor=#FFF0CC;strokeColor=#B77913;fontColor=#553609;strokeWidth=2;",
}


def chart_xml(title, note, nodes, edges):
    kinds = {node_id: kind for node_id, kind, *_ in nodes}
    assert sum(kind == "terminal" and text == "Start" for _, kind, text, *_ in nodes) == 1
    assert sum(kind == "terminal" and text == "End" for _, kind, text, *_ in nodes) == 1
    outgoing = {}
    for source, target, *label in edges:
        assert source in kinds and target in kinds
        outgoing.setdefault(source, []).append(label[0] if label else "")
    for node_id, kind, *_ in nodes:
        if kind == "decision":
            assert sorted(outgoing[node_id]) == ["No", "Yes"], (title, node_id)

    model = ET.Element("mxGraphModel", {
        "dx": "1600", "dy": "900", "grid": "1", "gridSize": "10", "guides": "1",
        "tooltips": "1", "connect": "1", "arrows": "1", "fold": "1", "page": "1",
        "pageScale": "1", "pageWidth": "1350", "pageHeight": str(max(1169, 270 + 125 * max(row for *_, row in nodes))),
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
    ET.SubElement(header, "mxGeometry", {"x": "65", "y": "25", "width": "1200", "height": "40", "as": "geometry"})
    for node_id, kind, label, col, row in nodes:
        width = 265 if kind != "decision" else 290
        height = 68 if kind != "decision" else 100
        cell = ET.SubElement(root, "mxCell", {
            "id": node_id, "value": label, "style": STYLE[kind] + "fontSize=13;align=center;verticalAlign=middle;spacing=8;",
            "vertex": "1", "parent": "1",
        })
        ET.SubElement(cell, "mxGeometry", {
            "x": str(65 + col * 365), "y": str(95 + row * 125),
            "width": str(width), "height": str(height), "as": "geometry",
        })
    for index, (source, target, *edge_label) in enumerate(edges):
        cell = ET.SubElement(root, "mxCell", {
            "id": f"edge{index}", "value": edge_label[0] if edge_label else "",
            "style": "edgeStyle=orthogonalEdgeStyle;rounded=1;orthogonalLoop=1;jettySize=auto;html=1;endArrow=block;endFill=1;strokeColor=#5B7064;fontSize=12;fontStyle=1;labelBackgroundColor=#FFFFFF;",
            "edge": "1", "parent": "1", "source": source, "target": target,
        })
        ET.SubElement(cell, "mxGeometry", {"relative": "1", "as": "geometry"})
    return model


def main():
    document = ET.Element("mxfile", {
        "host": "app.diagrams.net", "modified": "2026-10-15T00:00:00.000Z",
        "agent": "Codex", "version": "24.7.17", "type": "device",
    })
    for index, (title, note, nodes, edges) in enumerate(CHARTS, 1):
        diagram = ET.SubElement(document, "diagram", {"id": f"passenger-page-{index}", "name": title})
        diagram.append(chart_xml(title, note, nodes, edges))
    output = Path(__file__).with_name("passenger_page_flowcharts.drawio")
    ET.ElementTree(document).write(output, encoding="utf-8", xml_declaration=True)
    print(f"Created {output} with {len(CHARTS)} page flowcharts")


if __name__ == "__main__":
    main()
