/* static/admin/js/class_time_filter.js (최종 통합본) */

(function($) {
    /**
     * [설정] 과목별 필터링 규칙 및 선생님 필드 매핑
     */
    const FIELD_RULES = [
        { 
            suffix: 'syntax_class', 
            teacherSuffix: 'syntax_teacher', // 담당 선생님 필드명 (중복 체크용)
            keyword: '구문', 
            typeDependency: false,
            role: 'syntax' // API 요청용 역할명
        },
        { 
            suffix: 'reading_class', 
            teacherSuffix: 'reading_teacher', 
            keyword: '독해', 
            typeDependency: false,
            role: 'reading'
        },
        { 
            suffix: 'extra_class', 
            teacherSuffix: 'extra_class_teacher', 
            keyword: '',     
            typeDependency: true, // 추가 수업은 타입(구문/독해) 선택에 따라 갈림
            role: 'extra'
        }
    ];

    $(document).ready(function() {
        console.log("🚀 통합 시간표 필터 (지점+타입+요일+마감체크) 시작");

        // 1. 로드 시 모든 행 초기화
        $('select[name$="-branch"]').each(function() {
            initializeRow($(this));
        });

        // 2. 행 추가 시 초기화
        $(document).on('formset:added', function(event, $row, formsetName) {
            $row.find('select[name$="-branch"]').each(function() {
                initializeRow($(this));
            });
        });
    });

    function initializeRow($branchSelect) {
        const branchId = $branchSelect.attr('id'); 
        if (!branchId) return;

        const prefix = branchId.substring(0, branchId.lastIndexOf('-'));
        
        const targets = [];

        FIELD_RULES.forEach(function(rule) {
            // 시간표 선택 박스 찾기
            const $select = $('#' + prefix + '-' + rule.suffix);
            // 선생님 선택 박스 찾기
            const $teacherSelect = $('#' + prefix + '-' + rule.teacherSuffix);

            if ($select.length > 0) {
                // (1) 요일 필터 생성
                createDayFilter($select);

                // (2) 타겟 정보 저장
                const targetObj = {
                    $el: $select, // 시간표 박스
                    $teacherEl: $teacherSelect, // 선생님 박스
                    keyword: rule.keyword,
                    rule: rule,
                    prefix: prefix
                };
                
                // (3) 선생님 변경 시 -> 마감 체크 재실행
                if ($teacherSelect.length > 0) {
                    $teacherSelect.on('change', function() {
                        checkOccupancy(targetObj);
                    });
                }

                // (4) '추가수업'인 경우 타입 박스 연동
                if (rule.typeDependency) {
                    const $typeSelect = $('#' + prefix + '-extra_class_type');
                    if ($typeSelect.length > 0) {
                        targetObj.$typeEl = $typeSelect;
                        $typeSelect.on('change', function() {
                            renderOptions(targetObj); 
                        });
                    }
                }

                targets.push(targetObj);

                // (5) 수정 페이지 진입 시: 현재 HTML에 있는 옵션을 '원본'으로 저장
                if ($select.find('option').length > 1) {
                    $select.data('master-options', $select.find('option').clone());
                    // 로딩 직후 마감 체크 한 번 실행
                    checkOccupancy(targetObj);
                }
            }
        });

        // 3. 지점 변경 시 -> 서버에서 새 목록 받아오기
        $branchSelect.off('change.classTimeFilter').on('change.classTimeFilter', function() {
            updateClassTimes($(this).val(), targets);
        });
        
        // 4. (수정 모드) 이미 지점이 선택되어 있다면 시간표 데이터 초기화
        //    (주의: 페이지 로드 시 Django가 전체 목록을 렌더링했을 수 있으므로, 지점 목록으로 필터링)
        if ($branchSelect.val()) {
            updateClassTimes($branchSelect.val(), targets);
        }
    }

    // [UI] 요일 필터 만들기
    function createDayFilter($select) {
        if ($select.prev('.day-filter-box').length > 0) return;

        const $dayFilter = $('<select class="day-filter-box" style="margin-right:5px; width:90px;">')
            .append('<option value="">📅 요일</option>')
            .append('<option value="월요일">월요일</option>')
            .append('<option value="화요일">화요일</option>')
            .append('<option value="수요일">수요일</option>')
            .append('<option value="목요일">목요일</option>')
            .append('<option value="금요일">금요일</option>')
            .append('<option value="토요일">토요일</option>')
            .append('<option value="일요일">일요일</option>');

        $select.before($dayFilter);

        // 요일 변경 시 -> 목록 다시 그리기
        $dayFilter.on('change', function() {
            // 이벤트가 발생한 요일 필터 바로 뒤에 있는 select 박스를 찾아서 처리
            const $relatedSelect = $(this).next('select');
            // targets 배열에서 해당 select와 매칭되는 객체를 찾기는 어려우므로
            // DOM에서 역으로 추적하여 필터링 수행
            applyDayFilter($relatedSelect, $(this).val());
        });
    }

    // [AJAX] 데이터 가져오기
    function updateClassTimes(branchId, targets) {
        if (!branchId) {
            targets.forEach(t => {
                t.$el.html('<option value="">---------</option>');
                t.$el.data('master-options', null);
                t.$el.prev('.day-filter-box').val('');
            });
            return;
        }

        $.ajax({
            url: '/core/api/get-classtimes/',
            data: { 'branch_id': branchId },
            success: function(data) {
                targets.forEach(function(target) {
                    // 1. 키워드(구문/독해)로 1차 분류하여 'Master Data' 생성
                    let filteredHtml = '<option value="">---------</option>';
                    $.each(data, function(idx, item) {
                        if (target.keyword === "" || item.name.indexOf(target.keyword) !== -1) {
                            filteredHtml += '<option value="' + item.id + '">' + item.name + '</option>';
                        }
                    });

                    // 2. Master Data 저장
                    const $newOptions = $(filteredHtml);
                    target.$el.data('master-options', $newOptions); 
                    
                    // 3. 화면 렌더링 & 마감 체크
                    renderOptions(target);
                    
                    // 4. 요일 필터 초기화
                    target.$el.prev('.day-filter-box').val('');
                });
            },
            error: function(xhr, status, error) {
                console.error("시간표 불러오기 실패:", error);
            }
        });
    }

    // [화면 그리기] Master Data -> 타입 필터 -> 요일 필터 -> DOM 적용 -> [마감 체크]
    function renderOptions(target) {
        const $select = target.$el;
        const $master = $select.data('master-options');
        if (!$master) return;

        let $options = $master.clone();

        // 1. 추가수업 타입 필터
        if (target.rule.typeDependency && target.$typeEl) {
            const typeVal = target.$typeEl.val(); 
            if (typeVal === 'SYNTAX') {
                $options = $options.filter((i, el) => el.value === "" || $(el).text().indexOf('구문') !== -1);
            } else if (typeVal === 'READING') {
                $options = $options.filter((i, el) => el.value === "" || $(el).text().indexOf('독해') !== -1);
            }
        }

        // 2. 요일 필터
        const $dayFilter = $select.prev('.day-filter-box');
        if ($dayFilter.length > 0) {
            const dayVal = $dayFilter.val();
            if (dayVal) {
                $options = $options.filter((i, el) => el.value === "" || $(el).text().indexOf(dayVal) !== -1);
            }
        }

        // 3. DOM 적용
        const currentVal = $select.val();
        $select.empty().append($options);
        if (currentVal) $select.val(currentVal);

        // 4. ✅ [핵심] 렌더링 직후 마감 여부 체크 실행
        checkOccupancy(target);
    }

    // 요일 필터 전용 함수 (renderOptions와 유사하지만 타겟 객체 없이 DOM만으로 동작)
    function applyDayFilter($select, dayVal) {
        const $master = $select.data('master-options');
        if (!$master) return;

        let $options = $master.clone();
        
        // 추가수업 타입 필터 (DOM에서 찾기)
        const nameAttr = $select.attr('name');
        if (nameAttr && nameAttr.indexOf('extra_class') !== -1) {
            const prefix = $select.attr('id').replace('-extra_class', '');
            const $typeEl = $('#' + prefix + '-extra_class_type');
            if ($typeEl.length > 0) {
                const typeVal = $typeEl.val();
                if (typeVal === 'SYNTAX') {
                    $options = $options.filter((i, el) => el.value === "" || $(el).text().indexOf('구문') !== -1);
                } else if (typeVal === 'READING') {
                    $options = $options.filter((i, el) => el.value === "" || $(el).text().indexOf('독해') !== -1);
                }
            }
        }

        if (dayVal) {
            $options = $options.filter((i, el) => el.value === "" || $(el).text().indexOf(dayVal) !== -1);
        }

        const currentVal = $select.val();
        $select.empty().append($options);
        if (currentVal) $select.val(currentVal);

        // 요일 변경 후에도 마감 체크를 위해 이벤트 트리거 (또는 직접 함수 호출이 좋지만 여기선 약식으로)
        // DOM에서 teacher select를 찾아야 함
        const prefix = $select.attr('id').substring(0, $select.attr('id').lastIndexOf('-'));
        // suffix 추론
        let teacherSuffix = '';
        if (nameAttr.includes('syntax')) teacherSuffix = 'syntax_teacher';
        else if (nameAttr.includes('reading')) teacherSuffix = 'reading_teacher';
        else if (nameAttr.includes('extra')) teacherSuffix = 'extra_class_teacher';

        const $teacherSelect = $('#' + prefix + '-' + teacherSuffix);
        // 임시 타겟 객체 생성하여 체크 실행
        checkOccupancy({
            $el: $select,
            $teacherEl: $teacherSelect,
            rule: { role: (nameAttr.includes('extra') ? 'extra' : (nameAttr.includes('syntax') ? 'syntax' : 'reading')) }
        });
    }

    // [마감 체크] API 호출하여 중복/마감된 시간표 비활성화
    function checkOccupancy(target) {
        const $teacher = target.$teacherEl;
        const $classTime = target.$el;
        
        if (!$teacher || $teacher.length === 0) return;

        const teacherId = $teacher.val();
        if (!teacherId) {
            // 선생님 선택 해제 시 마감 표시 제거
            $classTime.find('option').prop('disabled', false).each(function() {
                $(this).text($(this).text().replace(' ⛔(마감)', ''));
            });
            return;
        }

        // 현재 학생 ID 추출 (자기 자신과의 중복은 허용하기 위해)
        const urlMatch = window.location.pathname.match(/studentuser\/(\d+)\/change/);
        const currentStudentId = urlMatch ? urlMatch[1] : null;

        $.ajax({
            url: '/academy/api/admin/teacher-schedule/',
            data: {
                'teacher_id': teacherId,
                'subject': target.rule.role,
                'current_student_id': currentStudentId
            },
            success: function(response) {
                const occupiedIds = response.occupied_ids;
                const currentVal = parseInt($classTime.val());

                $classTime.find('option').each(function() {
                    const optVal = parseInt($(this).val());
                    if (isNaN(optVal)) return;

                    // 기존 마감 텍스트 제거 (중복 방지)
                    let text = $(this).text().replace(' ⛔(마감)', '');

                    const isOccupied = occupiedIds.includes(optVal);
                    // 이미 선택되어 있는 값은 마감이어도 유지(수정 가능하게)
                    const isSelected = (optVal === currentVal);

                    if (isOccupied && !isSelected) {
                        $(this).prop('disabled', true);
                        $(this).css({ 'color': '#cccccc', 'font-style': 'italic' });
                        $(this).text(text + ' ⛔(마감)');
                    } else {
                        $(this).prop('disabled', false);
                        $(this).css({ 'color': '', 'font-style': '' });
                        $(this).text(text);
                    }
                });
            }
        });
    }

})(django.jQuery);