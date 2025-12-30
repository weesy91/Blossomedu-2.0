/* static/admin/js/schedule_filter.js (최종 수정판) */

document.addEventListener('DOMContentLoaded', function() {
    console.log("✅ 스케줄 필터 스크립트가 로드되었습니다!"); // F12 콘솔 확인용

    // 요소 가져오기
    const subjectSelect = document.getElementById('id_subject');
    const targetSelect = document.getElementById('id_target_class');
    const extraCheckbox = document.getElementById('id_is_extra_class');
    const newDateInput = document.getElementById('id_new_date');
    const originalDateRow = document.querySelector('.field-original_date'); 

    // 요일 이름 정의 (ClassTime 이름에 들어있는 것과 똑같아야 함)
    const dayNames = ['일요일', '월요일', '화요일', '수요일', '목요일', '금요일', '토요일'];

    // ===============================================
    // 필터링 함수
    // ===============================================
    function updateFilters() {
        if (!targetSelect) return;

        const selectedSubject = subjectSelect.value;
        const dateValue = newDateInput.value;
        
        let targetDayString = "";
        
        // 날짜가 있으면 요일(문자열)을 구합니다.
        if (dateValue) {
            const dateObj = new Date(dateValue);
            if (!isNaN(dateObj)) {
                const dayIndex = dateObj.getDay(); // 0(일) ~ 6(토)
                targetDayString = dayNames[dayIndex];
                // console.log("날짜 감지됨:", dateValue, targetDayString);
            }
        }

        const options = targetSelect.options;

        for (let i = 0; i < options.length; i++) {
            const opt = options[i];
            const text = opt.text; 

            if (opt.value === "") continue; // 빈칸 패스

            // 1. 과목 필터링
            let matchSubject = true;
            if (selectedSubject === 'SYNTAX' && text.includes('독해')) matchSubject = false;
            if (selectedSubject === 'READING' && text.includes('구문')) matchSubject = false;

            // 2. 요일 필터링 (날짜가 선택된 경우에만)
            let matchDay = true;
            if (targetDayString && !text.includes(targetDayString)) {
                matchDay = false;
            }

            // 표시 여부 결정
            if (matchSubject && matchDay) {
                opt.style.display = 'block';
            } else {
                opt.style.display = 'none';
            }
        }
    }

    // ===============================================
    // 날짜 입력칸 숨김 함수
    // ===============================================
    function toggleOriginalDate() {
        if (extraCheckbox && originalDateRow) {
            originalDateRow.style.display = extraCheckbox.checked ? 'none' : 'block';
        }
    }

    // ===============================================
    // 이벤트 리스너 등록
    // ===============================================
    
    // 1. 과목 바꿀 때
    if (subjectSelect) subjectSelect.addEventListener('change', updateFilters);
    
    // 2. 날짜 바꿀 때 (달력 위젯 대응을 위해 여러 이벤트 등록)
    if (newDateInput) {
        newDateInput.addEventListener('change', updateFilters);
        newDateInput.addEventListener('input', updateFilters);
        newDateInput.addEventListener('blur', updateFilters);
    }
    
    // 3. 체크박스 바꿀 때
    if (extraCheckbox) extraCheckbox.addEventListener('change', toggleOriginalDate);

    // [핵심] 달력 아이콘으로 날짜를 찍었을 때를 대비한 안전장치
    // 화면 아무 곳이나 클릭하면 0.5초 뒤에 필터링을 한 번 더 돌립니다.
    document.addEventListener('click', function() {
        setTimeout(updateFilters, 500); 
    });

    // 처음 로딩 시 실행
    updateFilters();
    toggleOriginalDate();
});