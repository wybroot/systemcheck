from flask import Blueprint, render_template, request

inspections_bp = Blueprint('inspections', __name__)

@inspections_bp.route('/')
def list_inspections():
    return render_template('web/inspections.html')

@inspections_bp.route('/<int:inspection_id>')
def inspection_detail(inspection_id):
    return render_template('web/inspection_detail.html', inspection_id=inspection_id)

@inspections_bp.route('/run', methods=['GET', 'POST'])
def run_inspection():
    server_ids = request.args.get('server_ids', '')
    return render_template('web/run_inspection.html', server_ids=server_ids)

@inspections_bp.route('/history')
def history():
    return render_template('web/history.html')