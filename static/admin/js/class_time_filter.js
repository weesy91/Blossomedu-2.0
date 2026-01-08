/* static/admin/js/class_time_filter.js */

(function($) {
    const FIELD_RULES = [
        { suffix: 'syntax_class', teacherSuffix: 'syntax_teacher', keyword: '구문', role: 'syntax', typeDependency: false },
        { suffix: 'reading_class', teacherSuffix: 'reading_teacher', keyword: '독해', role: 'reading', typeDependency: false },
        { suffix: 'extra_class', teacherSuffix: 'extra_class_teacher', keyword: '', role: 'extra', typeDependency: true }
    ];

    $(document).ready(function() {
        console.log("🚀 [System Refactor] 통합 스케줄링 시스템 가동");

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

        const targets = [];

        FIELD_RULES.forEach(function(rule) {
            const $timeSelect = $('#' + prefix + '-' + rule.suffix);
            const $teacherSelect = $('#' + prefix + '-' + rule.teacherSuffix);

            if ($timeSelect.length) {
                const targetObj = { 
                    $el: $timeSelect, 
                    $teacherEl: $teacherSelect, 
                    rule: rule, 
                    prefix: prefix 
                };
                
                // (1) 요일 필터 UI 부착
                attachDayFilter($timeSelect);

                // (2) 이벤트 연결
                // 지점 변경 시 -> 갱신
                $branchSelect.on('change', () => fetchAndRender(targetObj, $branchSelect.val()));
                
                // 선생님 변경 시 -> 갱신 (마감 정보가 달라지므로)
                if ($teacherSelect.length) {
                    $teacherSelect.on('change', () => fetchAndRender(targetObj, $branchSelect.val()));
                }

                // 추가수업 타입 변경 시 -> 갱신 (키워드 필터가 달라지므로)
                if (rule.typeDependency) {
                    const $typeSelect = $('#' + prefix + '-extra_class_type');
                    targetObj.$typeEl = $typeSelect;
                    $typeSelect.on('change', () => fetchAndRender(targetObj, $branchSelect.val()));
                }

                targets.push(targetObj);

                // (3) 초기 로드 시 데이터 갱신 (수정 모드 대응)
                if ($branchSelect.val()) {
                    fetchAndRender(targetObj, $branchSelect.val());
                }
            }
        });
    }

    function fetchAndRender(target, branchId) {
        if (!branchId) {
            target.$el.html('<option value="">---------</option>');
            return;
        }

        const teacherId = target.$teacherEl ? target.$teacherEl.val() : '';
        const currentStudentId = (window.location.pathname.match(/studentuser\/(\d+)\/change/) || [])[1] || '';

        // API 호출
        $.ajax({
            url: '/core/api/get-classtimes/',
            data: {
                'branch_id': branchId,
                'teacher_id': teacherId,
                'role': target.rule.role,
                'student_id': currentStudentId
            },
            success: function(data) {
                // data = [{id, name, disabled, raw_name}, ...]
                renderOptions(target, data);
            }
        });
    }

    function renderOptions(target, data) {
        const $select = target.$el;
        const currentVal = $select.val();
        const $dayFilter = $select.prev('.day-filter-box');
        const selectedDay = $dayFilter.length ? $dayFilter.val() : '';

        let html = '<option value="">---------</option>';

        // 1. 키워드 필터 결정
        let keyword = target.rule.keyword;
        if (target.rule.typeDependency && target.$typeEl) {
            const typeVal = target.$typeEl.val();
            if (typeVal === 'SYNTAX') keyword = '구문';
            else if (typeVal === 'READING') keyword = '독해';
        }

        data.forEach(function(item) {
            // (A) 키워드 필터링 (구문/독해 분류)
            if (keyword && item.raw_name.indexOf(keyword) === -1) return;

            // (B) 요일 필터링
            if (selectedDay && item.name.indexOf(selectedDay) === -1) return;

            // (C) 옵션 생성 (disabled 적용)
            // 현재 선택된 값은 마감이어도 선택 유지 (disabled 안 함)
            const isSelected = (String(item.id) === String(currentVal));
            const disabledAttr = (item.disabled && !isSelected) ? 'disabled' : '';
            const style = (item.disabled && !isSelected) ? 'style="color:#ccc; font-style:italic;"' : '';

            html += `<option value="${item.id}" ${disabledAttr} ${style}>${item.name}</option>`;
        });

        $select.html(html);
        if (currentVal) $select.val(currentVal);
    }

    function attachDayFilter($select) {
        if ($select.prev('.day-filter-box').length) return;
        const $filter = $('<select class="day-filter-box" style="margin-right:5px; width:80px;"><option value="">요일</option><option value="월요일">월</option><option value="화요일">화</option><option value="수요일">수</option><option value="목요일">목</option><option value="금요일">금</option><option value="토요일">토</option><option value="일요일">일</option></select>');
        $select.before($filter);
        // 요일 변경 시 -> 전체 데이터는 그대로 두고 다시 그리기(fetch까지 할 필요는 없지만 로직 단순화를 위해 트리거)
        $filter.on('change', function() {
            $select.trigger('change.classTimeFilter_internal_refresh'); // 단순 트리거보다는 상위 로직 재호출이 맞음.
            // 여기서는 간단하게 브랜치 변경 이벤트를 흉내내거나, 저장된 데이터를 쓰는데
            // 가장 확실한 건 해당 row의 branch select change 이벤트를 트리거하는 것임.
            const branchSelectId = $select.attr('id').split('-').slice(0, 2).join('-') + '-branch';
            $('#' + branchSelectId).trigger('change');
        });
    }

})(django.jQuery);