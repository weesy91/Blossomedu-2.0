/* static/admin/js/class_time_filter.js */

(function($) {
    // 과목별 설정: 어떤 선생님 필드와 연결되는지, 어떤 키워드(구문/독해)를 보여줄지
    const FIELD_RULES = [
        { suffix: 'syntax_class', teacherSuffix: 'syntax_teacher', keyword: '구문', role: 'syntax', typeDependency: false },
        { suffix: 'reading_class', teacherSuffix: 'reading_teacher', keyword: '독해', role: 'reading', typeDependency: false },
        { suffix: 'extra_class', teacherSuffix: 'extra_class_teacher', keyword: '', role: 'extra', typeDependency: true }
    ];

    $(document).ready(function() {
        // 1. 페이지 로드 시 초기화
        $('select[name$="-branch"]').each(function() { initializeRow($(this)); });

        // 2. '추가' 버튼으로 행이 늘어날 때 초기화
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
                    rule: rule, 
                    prefix: prefix 
                };

                // (2) 추가수업은 '타입(구문/독해)' 선택 박스도 찾음
                if (rule.typeDependency) {
                    targetObj.$typeEl = $('#' + prefix + '-extra_class_type');
                }

                // (3) 이벤트 연결: 지점/선생님/타입이 바뀌면 -> 서버에서 목록 새로 받기
                $branchSelect.on('change', () => fetchTimes(targetObj, $branchSelect.val()));
                
                if ($teacherSelect.length) {
                    $teacherSelect.on('change', () => fetchTimes(targetObj, $branchSelect.val()));
                }

                if (targetObj.$typeEl) {
                    targetObj.$typeEl.on('change', () => fetchTimes(targetObj, $branchSelect.val()));
                }

                // (4) 요일 변경 시 -> 서버 요청 없이 화면만 다시 그림 (속도 향상)
                $dayFilter.on('change', () => renderOptions(targetObj));

                // (5) 수정 모드(이미 값이 있는 경우) 초기 실행
                if ($branchSelect.val()) {
                    fetchTimes(targetObj, $branchSelect.val());
                }
            }
        });
    }

    // [UI] 요일 필터 생성
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

    // [AJAX] 서버에서 시간표(+마감정보) 가져오기
    function fetchTimes(target, branchId) {
        if (!branchId) {
            target.$el.html('<option value="">---------</option>');
            return;
        }

        const teacherId = target.$teacherEl ? target.$teacherEl.val() : '';
        const currentStudentId = (window.location.pathname.match(/studentuser\/(\d+)\/change/) || [])[1] || '';

        $.ajax({
            url: '/core/api/get-classtimes/',
            data: {
                'branch_id': branchId,
                'teacher_id': teacherId,
                'role': target.rule.role,
                'student_id': currentStudentId
            },
            success: function(data) {
                // 데이터를 DOM에 저장해두고, 요일 필터 시 재사용
                target.$el.data('cached-times', data);
                renderOptions(target);
            }
        });
    }

    // [Render] 저장된 데이터를 화면에 그리기
    function renderOptions(target) {
        const data = target.$el.data('cached-times');
        if (!data) return;

        const currentVal = target.$el.val();
        const selectedDay = target.$dayFilter.val();

        // 키워드 결정 (구문/독해)
        let keyword = target.rule.keyword;
        if (target.rule.typeDependency && target.$typeEl) {
            const typeVal = target.$typeEl.val();
            if (typeVal === 'SYNTAX') keyword = '구문';
            else if (typeVal === 'READING') keyword = '독해';
        }

        let html = '<option value="">---------</option>';

        data.forEach(function(item) {
            // (A) 키워드 필터 (구문 vs 독해)
            if (keyword && item.raw_name.indexOf(keyword) === -1) return;

            // (B) 요일 필터
            if (selectedDay && item.name.indexOf(selectedDay) === -1) return;

            // (C) 마감(Disabled) 처리
            // 내 수업(현재 선택값)은 마감이어도 선택 유지, 아니면 비활성화
            const isSelected = (String(item.id) === String(currentVal));
            let disabledAttr = '';
            let styleAttr = '';

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