/* static/admin/js/class_time_filter.js */

(function($) {
    const FIELD_RULES = [
        { suffix: 'syntax_class', teacherSuffix: 'syntax_teacher', keyword: '구문', role: 'syntax', typeDependency: false },
        { suffix: 'reading_class', teacherSuffix: 'reading_teacher', keyword: '독해', role: 'reading', typeDependency: false },
        { suffix: 'extra_class', teacherSuffix: 'extra_class_teacher', keyword: '', role: 'extra', typeDependency: true }
    ];

    $(document).ready(function() {
        console.log("🚀 [System V6] 구문 1:1 중복방지 필터 가동");

        // 초기화
        $('select[name$="-branch"]').each(function() { initializeRow($(this)); });
        $(document).on('formset:added', function(e, $row) {
            $row.find('select[name$="-branch"]').each(function() { initializeRow($(this)); });
        });
    });

    function initializeRow($branchSelect) {
        const branchId = $branchSelect.attr('id');
        if (!branchId) return;
        const prefix = branchId.substring(0, branchId.lastIndexOf('-'));

        FIELD_RULES.forEach(function(rule) {
            const $timeSelect = $('#' + prefix + '-' + rule.suffix);
            const $teacherSelect = $('#' + prefix + '-' + rule.teacherSuffix);

            if ($timeSelect.length) {
                // (1) 요일 필터 생성
                const $dayFilter = createDayFilter($timeSelect);

                const targetObj = { 
                    $el: $timeSelect, 
                    $teacherEl: $teacherSelect,
                    $dayFilter: $dayFilter,
                    rule: rule 
                };

                // (2) 보충수업용 타입 선택 박스 찾기
                if (rule.typeDependency) {
                    targetObj.$typeEl = $('#' + prefix + '-extra_class_type');
                }

                // (3) 이벤트 연결: 조건이 바뀌면 무조건 서버에 다시 물어봄
                // 지점 변경
                $branchSelect.on('change', () => fetchTimes(targetObj, $branchSelect.val()));
                
                // 선생님 변경 (마감 정보가 달라지므로 필수)
                if ($teacherSelect.length) {
                    $teacherSelect.on('change', () => fetchTimes(targetObj, $branchSelect.val()));
                }

                // 타입 변경 (구문이냐 독해냐에 따라 마감 여부가 달라지므로 필수)
                if (targetObj.$typeEl) {
                    targetObj.$typeEl.on('change', () => fetchTimes(targetObj, $branchSelect.val()));
                }

                // 요일 변경 (서버 안 가고 화면에서만 거름)
                $dayFilter.on('change', () => renderOptions(targetObj));

                // 초기 실행
                if ($branchSelect.val()) {
                    fetchTimes(targetObj, $branchSelect.val());
                }
            }
        });
    }

    function createDayFilter($select) {
        if ($select.prev('.day-filter-box').length > 0) return $select.prev('.day-filter-box');
        
        const $filter = $('<select class="day-filter-box" style="margin-right:5px; width:80px; padding:2px;">')
            .append('<option value="">📅 요일</option>')
            .append('<option value="월요일">월요일</option>')
            .append('<option value="화요일">화요일</option>')
            .append('<option value="수요일">수요일</option>')
            .append('<option value="목요일">목요일</option>')
            .append('<option value="금요일">금요일</option>')
            .append('<option value="토요일">토요일</option>')
            .append('<option value="일요일">일요일</option>');
        
        $select.before($filter);
        return $filter;
    }

    function fetchTimes(target, branchId) {
        if (!branchId) {
            target.$el.html('<option value="">---------</option>');
            return;
        }

        const teacherId = target.$teacherEl ? target.$teacherEl.val() : '';
        const currentStudentId = (window.location.pathname.match(/studentuser\/(\d+)\/change/) || [])[1] || '';
        
        // [핵심] 보충수업일 경우, 현재 선택된 타입(구문/독해)을 서버에 알려줌
        let extraType = '';
        if (target.rule.typeDependency && target.$typeEl) {
            extraType = target.$typeEl.val(); // 'SYNTAX' or 'READING'
        }

        $.ajax({
            url: '/core/api/get-classtimes/',
            data: {
                'branch_id': branchId,
                'teacher_id': teacherId,
                'role': target.rule.role, // 'syntax', 'reading', 'extra'
                'type': extraType,        // [NEW] 보충수업 타입 전달
                'student_id': currentStudentId
            },
            success: function(data) {
                target.$el.data('cached-times', data);
                renderOptions(target);
            }
        });
    }

    function renderOptions(target) {
        const data = target.$el.data('cached-times');
        if (!data) return;

        const currentVal = target.$el.val();
        const selectedDay = target.$dayFilter.val();

        // 필터링 키워드 결정
        let keyword = target.rule.keyword;
        if (target.rule.typeDependency && target.$typeEl) {
            const typeVal = target.$typeEl.val();
            if (typeVal === 'SYNTAX') keyword = '구문';
            else if (typeVal === 'READING') keyword = '독해';
        }

        let html = '<option value="">---------</option>';

        data.forEach(function(item) {
            // 키워드 필터
            if (keyword && item.raw_name.indexOf(keyword) === -1) return;
            // 요일 필터
            if (selectedDay && item.name.indexOf(selectedDay) === -1) return;

            // [마감 처리]
            const isSelected = (String(item.id) === String(currentVal));
            let disabledAttr = '';
            let styleAttr = '';

            // 내 수업이 아니고, disabled 플래그가 있으면 -> 비활성화
            if (item.disabled && !isSelected) {
                disabledAttr = 'disabled';
                styleAttr = 'style="color:#ccc; background-color:#f0f0f0; font-style:italic;"';
            }

            html += `<option value="${item.id}" ${disabledAttr} ${styleAttr}>${item.name}</option>`;
        });

        target.$el.html(html);
        if (currentVal) target.$el.val(currentVal);
    }

})(django.jQuery);