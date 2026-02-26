from flask import Blueprint, render_template, request, redirect, url_for, flash

servers_bp = Blueprint('servers', __name__)

@servers_bp.route('/')
def list_servers():
    return render_template('web/servers.html')

@servers_bp.route('/<int:server_id>')
def server_detail(server_id):
    return render_template('web/server_detail.html', server_id=server_id)

@servers_bp.route('/add', methods=['GET', 'POST'])
def add_server():
    return render_template('web/server_form.html')

@servers_bp.route('/<int:server_id>/edit', methods=['GET', 'POST'])
def edit_server(server_id):
    return render_template('web/server_form.html', server_id=server_id)

@servers_bp.route('/<int:server_id>/inspect', methods=['POST'])
def inspect_server(server_id):
    return redirect(url_for('inspections.inspection_detail', server_id=server_id))